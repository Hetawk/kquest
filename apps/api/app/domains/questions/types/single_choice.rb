module Questions
  module Types
    class SingleChoice
      MIN_OPTIONS = 2
      MAX_OPTIONS = 6
      MAX_PROMPT_LENGTH = 500
      MAX_OPTION_LENGTH = 160
      MAX_POINTS = 1000

      def self.definition_errors(prompt:, options:, correct_option_id:, points:)
        errors = {}
        normalized_options = options.is_a?(Array) ? options : []

        errors[:prompt] = "must be between 1 and #{MAX_PROMPT_LENGTH} characters" unless
          prompt.is_a?(String) && prompt.strip.length.between?(1, MAX_PROMPT_LENGTH)

        errors[:options] = "must contain between #{MIN_OPTIONS} and #{MAX_OPTIONS} options" unless
          normalized_options.length.between?(MIN_OPTIONS, MAX_OPTIONS)

        option_ids = normalized_options.filter_map do |option|
          next unless option.is_a?(Hash)

          option["id"] || option[:id]
        end
        option_texts = normalized_options.filter_map do |option|
          next unless option.is_a?(Hash)

          option["text"] || option[:text]
        end

        errors[:options] = "must have unique identifiers and non-empty labels" unless
          option_ids.length == normalized_options.length &&
          option_ids.all? { |id| id.is_a?(String) && id.match?(/\A[0-9a-f-]{36}\z/i) } &&
          option_ids.uniq.length == option_ids.length &&
          option_texts.length == normalized_options.length &&
          option_texts.all? do |text|
            text.is_a?(String) && text.strip.length.between?(1, MAX_OPTION_LENGTH)
          end

        errors[:correct_option_id] = "must identify one of the available options" unless
          correct_option_id.is_a?(String) && option_ids.include?(correct_option_id)

        errors[:points] = "must be an integer between 1 and #{MAX_POINTS}" unless
          points.is_a?(Integer) && points.between?(1, MAX_POINTS)

        errors
      end

      def self.score(question:, selected_option_id:)
        selected_option_id == question.fetch("correct_option_id") ? question.fetch("points") : 0
      end
    end
  end
end
