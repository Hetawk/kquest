module Activities
  module Services
    class PublishActivity
      def self.call(activity:)
        Activity.transaction do
          activity.lock!
          if activity.status == "published"
            activity.errors.add(:status, "has already been published.")
            raise ActiveRecord::RecordInvalid, activity
          end
          if activity.questions.empty?
            activity.errors.add(:questions, "Add at least one question before publishing.")
            raise ActiveRecord::RecordInvalid, activity
          end

          questions = activity.questions.map do |question|
            question.attributes.slice(
              "id",
              "question_type",
              "position",
              "prompt",
              "options",
              "correct_option_id",
              "correct_option_ids",
              "points",
              "time_limit_seconds"
            )
          end
          questions.each { |question| question["speed_scoring"] = activity.speed_scoring? }
          if activity.shuffle_questions?
            questions.shuffle!
            questions.each_with_index { |question, index| question["position"] = index + 1 }
          end

          version = activity.activity_versions.create!(
            version_number: activity.activity_versions.maximum(:version_number).to_i + 1,
            title: activity.title,
            question_snapshot: questions,
            shuffle_questions: activity.shuffle_questions?,
            speed_scoring: activity.speed_scoring?,
            cover_image_url: activity.uploaded_asset&.public_url,
            published_at: Time.current
          )
          activity.update!(status: "published")
          version
        end
      end
    end
  end
end
