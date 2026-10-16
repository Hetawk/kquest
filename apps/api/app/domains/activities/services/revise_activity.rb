module Activities
  module Services
    class ReviseActivity
      class StaleRevision < StandardError
      end

      QUESTION_ID_REGEX = /\A[0-9a-f-]{36}\z/i

      def self.call(activity:, questions:, expected_version:, shuffle_questions:, speed_scoring:)
        Activity.transaction do
          activity.lock!
          latest_version = activity.activity_versions.order(:version_number).last
          unless activity.status == "published" && latest_version
            activity.errors.add(:status, "must be published before it can be revised.")
            raise ActiveRecord::RecordInvalid, activity
          end
          unless expected_version.is_a?(Integer) && expected_version.positive?
            activity.errors.add(:expected_version, "must be a positive integer.")
            raise ActiveRecord::RecordInvalid, activity
          end
          raise StaleRevision unless expected_version == latest_version.version_number
          unless [ true, false ].include?(shuffle_questions) && [ true, false ].include?(speed_scoring)
            activity.errors.add(:settings, "must include boolean shuffle and speed-scoring values.")
            raise ActiveRecord::RecordInvalid, activity
          end

          snapshot = normalize_questions(
            activity:,
            questions:,
            speed_scoring:
          )
          if shuffle_questions
            snapshot.shuffle!
            snapshot.each_with_index { |question, index| question["position"] = index + 1 }
          end

          version = activity.activity_versions.create!(
            version_number: latest_version.version_number + 1,
            question_snapshot: snapshot,
            shuffle_questions:,
            speed_scoring:,
            cover_image_url: latest_version.cover_image_url,
            published_at: Time.current
          )
          activity.touch
          version
        end
      end

      def self.normalize_questions(activity:, questions:, speed_scoring:)
        unless questions.is_a?(Array) && questions.any?
          activity.errors.add(:questions, "must contain at least one question.")
          raise ActiveRecord::RecordInvalid, activity
        end

        seen_question_ids = []
        normalized = questions.each_with_index.map do |raw_definition, index|
          definition = raw_definition.respond_to?(:to_h) ? raw_definition.to_h.stringify_keys : {}
          question_type = definition["question_type"]
          options = definition["options"].is_a?(Array) ? definition["options"].map do |option|
            option.respond_to?(:to_h) ? option.to_h.stringify_keys.slice("id", "text") : {}
          end : []
          correct_option_ids = definition["correct_option_ids"]
          correct_option_ids = [] unless correct_option_ids.is_a?(Array)
          correct_option_id = definition["correct_option_id"]
          correct_option_id = correct_option_ids.first if correct_option_id.blank?
          correct_option_id = correct_option_ids.first if question_type == "multiple_select"
          points = definition["points"]
          time_limit_seconds = definition["time_limit_seconds"]
          errors = case question_type
          when "single_choice"
            Questions::Types::SingleChoice.definition_errors(
              prompt: definition["prompt"],
              options:,
              correct_option_id:,
              points:,
              time_limit_seconds:
            )
          when "multiple_select"
            Questions::Types::MultipleSelect.definition_errors(
              prompt: definition["prompt"],
              options:,
              correct_option_ids:,
              points:,
              time_limit_seconds:
            )
          else
            { question_type: "must be single_choice or multiple_select" }
          end

          question_id = definition["id"]
          errors[:id] = "must be a unique UUID" unless
            question_id.is_a?(String) &&
            question_id.match?(QUESTION_ID_REGEX) &&
            !seen_question_ids.include?(question_id)
          seen_question_ids << question_id
          unless errors.empty?
            errors.each do |attribute, message|
              activity.errors.add(:questions, "Question #{index + 1} #{attribute} #{message}.")
            end
            raise ActiveRecord::RecordInvalid, activity
          end

          {
            "id" => question_id,
            "question_type" => question_type,
            "position" => index + 1,
            "prompt" => definition.fetch("prompt").strip,
            "options" => options.map { |option| { "id" => option.fetch("id"), "text" => option.fetch("text").strip } },
            "correct_option_id" => correct_option_id,
            "correct_option_ids" => question_type == "multiple_select" ? correct_option_ids : [ correct_option_id ],
            "points" => points,
            "time_limit_seconds" => time_limit_seconds,
            "speed_scoring" => speed_scoring
          }
        end

        normalized
      end
    end
  end
end
