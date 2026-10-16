module Questions
  module Types
    class SingleChoice
      MIN_OPTIONS = 2
      MAX_OPTIONS = 6
      MAX_PROMPT_LENGTH = 500
      MAX_OPTION_LENGTH = 160
      MAX_POINTS = 1000
      MAX_TIME_LIMIT_SECONDS = 300
      DEFAULT_TIME_LIMIT_SECONDS = 30

      def self.definition_errors(prompt:, options:, correct_option_id:, points:, time_limit_seconds:)
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

        errors[:time_limit_seconds] = "must be 0 (untimed) or between 5 and #{MAX_TIME_LIMIT_SECONDS}" unless
          time_limit_seconds.is_a?(Integer) &&
          (time_limit_seconds.zero? || time_limit_seconds.between?(5, MAX_TIME_LIMIT_SECONDS))

        errors
      end

      def self.score(question:, selected_option_id:)
        selected_option_id == question.fetch("correct_option_id") ? question.fetch("points") : 0
      end

      def self.score_with_speed(question:, selected_option_id:, elapsed_seconds:)
        Scoring.score_with_speed(
          question:,
          correct: selected_option_id == question.fetch("correct_option_id"),
          elapsed_seconds:
        )
      end

      def self.maximum_points(question)
        timed = question.fetch("time_limit_seconds", DEFAULT_TIME_LIMIT_SECONDS).positive?
        question.fetch("points") * (timed && question.fetch("speed_scoring", false) ? 2 : 1)
      end
    end
  end
end
