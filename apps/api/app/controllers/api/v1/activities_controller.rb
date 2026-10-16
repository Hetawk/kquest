module Api
  module V1
    class ActivitiesController < ApplicationController
      before_action :require_current_user

      def index
        return unless current_user

        activities = current_user.activities
          .includes(:questions, :activity_versions)
          .order(updated_at: :desc)
          .limit(100)
        plays_by_activity = Attempt.joins(activity_version: :activity)
          .where(activities: { user_id: current_user.id })
          .group("activities.id")
          .count
        total_activities = current_user.activities.count
        published_activities = current_user.activities.where(status: "published").count
        serialized_activities = activities.map do |activity|
          latest_version = activity.activity_versions.max_by(&:version_number)
          {
            id: activity.id,
            title: activity.title,
            description: activity.description,
            status: activity.status,
            question_count: latest_version&.question_snapshot&.length || activity.questions.size,
            share_code: latest_version&.share_code,
            version: latest_version&.version_number,
            total_plays: plays_by_activity.fetch(activity.id, 0),
            updated_at: (latest_version&.created_at || activity.updated_at).iso8601,
            published_at: latest_version&.published_at&.iso8601
          }
        end

        render json: {
          data: {
            activities: serialized_activities,
            summary: {
              total: total_activities,
              published: published_activities,
              plays: plays_by_activity.values.sum
            }
          }
        }
      end

      def show
        return unless current_user

        activity = current_user.activities
          .includes(:questions, :activity_versions)
          .find_by(id: params[:id])
        return render_not_found unless activity

        latest_version = activity.activity_versions.max_by(&:version_number)
        total_plays = Attempt.joins(activity_version: :activity)
          .where(activities: { id: activity.id })
          .count

        render json: {
          data: {
            id: activity.id,
            title: activity.title,
            description: activity.description,
            status: activity.status,
            question_count: latest_version&.question_snapshot&.length || activity.questions.size,
            share_code: latest_version&.share_code,
            version: latest_version&.version_number,
            total_plays:,
            updated_at: (latest_version&.created_at || activity.updated_at).iso8601,
            published_at: latest_version&.published_at&.iso8601,
            shuffle_questions: latest_version ? latest_version.shuffle_questions : activity.shuffle_questions?,
            speed_scoring: latest_version ? latest_version.speed_scoring : activity.speed_scoring?,
            questions: creator_questions(activity, latest_version)
          }
        }
      end

      def revise
        return unless current_user

        activity = current_user.activities.includes(:activity_versions).find_by(id: params[:activity_id])
        return render_not_found unless activity

        attributes = params.require(:revision).permit(
          :expected_version,
          :shuffle_questions,
          :speed_scoring,
          questions: [
            :id,
            :question_type,
            :prompt,
            :correct_option_id,
            :points,
            :time_limit_seconds,
            { correct_option_ids: [], options: [ :id, :text ] }
          ]
        )
        version = Activities::Services::ReviseActivity.call(
          activity:,
          questions: attributes[:questions],
          expected_version: attributes[:expected_version],
          shuffle_questions: attributes[:shuffle_questions],
          speed_scoring: attributes[:speed_scoring]
        )
        render(
          json: {
            data: {
              activity_id: activity.id,
              title: activity.title,
              version: version.version_number,
              share_code: version.share_code,
              play_path: "/play/#{version.share_code}"
            }
          },
          status: :created
        )
      rescue Activities::Services::ReviseActivity::StaleRevision
        render_error(
          code: "stale_activity_revision",
          message: "This quest changed in another session. Reload it before applying your edits.",
          status: :conflict
        )
      rescue ActiveRecord::RecordInvalid => error
        render_validation_error(error.record)
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "The submitted revision is invalid.",
          status: :unprocessable_entity
        )
      end

      def create
        return unless current_user

        attributes = params.require(:activity).permit(
          :title,
          :description,
          :cover_image_asset_id,
          :shuffle_questions,
          :speed_scoring,
          questions: [
            :question_type,
            :prompt,
            :correct_option_id,
            :points,
            :time_limit_seconds,
            { correct_option_ids: [], options: [ :id, :text ] }
          ]
        )
        question_definitions = attributes.delete(:questions) || []
        asset_id = attributes.delete(:cover_image_asset_id)
        uploaded_asset = current_user.uploaded_assets.find_by(id: asset_id) if asset_id.present?
        if asset_id.present? && !uploaded_asset
          return render_error(
            code: "invalid_cover_image",
            message: "Choose a cover image that you uploaded.",
            status: :unprocessable_entity
          )
        end

        activity = current_user.activities.build(
          title: attributes[:title],
          description: attributes[:description],
          uploaded_asset: uploaded_asset,
          shuffle_questions: ActiveModel::Type::Boolean.new.cast(attributes[:shuffle_questions]),
          speed_scoring: attributes[:speed_scoring].nil? || ActiveModel::Type::Boolean.new.cast(attributes[:speed_scoring])
        )
        question_definitions.each_with_index do |definition, index|
          question_type = definition[:question_type].presence || "single_choice"
          correct_option_ids = definition[:correct_option_ids] || []
          activity.questions.build(
            position: index + 1,
            question_type:,
            prompt: definition[:prompt],
            options: definition[:options]&.map(&:to_h),
            correct_option_id: definition[:correct_option_id] || correct_option_ids.first,
            correct_option_ids:,
            points: definition[:points],
            time_limit_seconds: definition[:time_limit_seconds] ||
              Questions::Types::SingleChoice::DEFAULT_TIME_LIMIT_SECONDS
          )
        end

        if activity.save
          render(
            json: {
              data: {
                id: activity.id,
                title: activity.title,
                description: activity.description,
                question_count: activity.questions.size,
                status: activity.status
              }
            },
            status: :created
          )
        else
          render_validation_error(activity)
        end
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "The submitted data is invalid.",
          status: :unprocessable_entity,
          details: { activity: [ { code: "required", message: "Activity details are required." } ] }
        )
      end

      private

      def creator_questions(activity, latest_version)
        if latest_version
          latest_version.question_snapshot.map do |question|
            {
              id: question.fetch("id"),
              position: question.fetch("position"),
              question_type: question.fetch("question_type", "single_choice"),
              prompt: question.fetch("prompt"),
              options: question.fetch("options"),
              correct_option_id: question.fetch("correct_option_id"),
              correct_option_ids: question.fetch("correct_option_ids", [ question.fetch("correct_option_id") ]),
              points: question.fetch("points"),
              time_limit_seconds: question.fetch("time_limit_seconds", 30)
            }
          end
        else
          activity.questions.map do |question|
            {
              id: question.id,
              position: question.position,
              question_type: question.question_type,
              prompt: question.prompt,
              options: question.options,
              correct_option_id: question.correct_option_id,
              correct_option_ids: question.correct_option_ids,
              points: question.points,
              time_limit_seconds: question.time_limit_seconds
            }
          end
        end
      end
    end
  end
end
