module Api
  module V1
    class ActivitiesController < ApplicationController
      before_action :prototype_api_only?
      before_action :require_current_user

      def create
        return unless current_user

        attributes = params.require(:activity).permit(
          :title,
          :description,
          :cover_image_asset_id,
          :shuffle_questions,
          :speed_scoring,
          questions: [ :prompt, :correct_option_id, :points, :time_limit_seconds, { options: [ :id, :text ] } ]
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
          activity.questions.build(
            position: index + 1,
            question_type: "single_choice",
            prompt: definition[:prompt],
            options: definition[:options]&.map(&:to_h),
            correct_option_id: definition[:correct_option_id],
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
    end
  end
end
