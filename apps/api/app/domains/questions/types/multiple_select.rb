module Questions
  module Types
    class MultipleSelect
      def self.definition_errors(prompt:, options:, correct_option_ids:, points:, time_limit_seconds:)
        errors = SingleChoice.definition_errors(
          prompt:,
          options:,
          correct_option_id: correct_option_ids.is_a?(Array) ? correct_option_ids.first : nil,
          points:,
          time_limit_seconds:
        )
        errors.delete(:correct_option_id)

        option_ids = options.is_a?(Array) ? options.filter_map do |option|
          next unless option.is_a?(Hash)

          option["id"] || option[:id]
        end : []
        valid = correct_option_ids.is_a?(Array) &&
          correct_option_ids.any? &&
          correct_option_ids.uniq == correct_option_ids &&
          (correct_option_ids - option_ids).empty?
        errors[:correct_option_ids] = "must identify one or more available options" unless valid

        errors
      end

      def self.score(question:, selected_option_ids:)
        selected = selected_option_ids.is_a?(Array) ? selected_option_ids : []
        correct = question.fetch("correct_option_ids", [ question.fetch("correct_option_id") ])
        selected.sort == correct.sort ? question.fetch("points") : 0
      end

      def self.score_with_speed(question:, selected_option_ids:, elapsed_seconds:)
        Scoring.score_with_speed(
          question:,
          correct: score(question:, selected_option_ids:).positive?,
          elapsed_seconds:
        )
      end

      def self.maximum_points(question)
        SingleChoice.maximum_points(question)
      end
    end
  end
end
