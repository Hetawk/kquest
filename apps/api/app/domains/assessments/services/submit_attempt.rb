module Assessments
  module Services
    class SubmitAttempt
      class InvalidResponses < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(activity_version:, learner_name:, responses:, submission_key:)
        normalized_responses = normalize_responses(activity_version, responses)
        raise InvalidResponses unless learner_name.is_a?(String) && learner_name.strip.length.between?(1, 80)

        existing_attempt = Attempt.find_by(submission_key: submission_key)
        return reuse_attempt(existing_attempt, learner_name, normalized_responses) if existing_attempt

        snapshots = activity_version.question_snapshot
        score = snapshots.sum do |question|
          response = normalized_responses.find { |item| item.fetch("question_id") == question.fetch("id") }
          Questions::Types::SingleChoice.score(
            question: question,
            selected_option_id: response.fetch("option_id")
          )
        end
        max_score = snapshots.sum { |question| question.fetch("points") }

        attempt = Attempt.create!(
          activity_version: activity_version,
          learner_name: learner_name.strip,
          submission_key: submission_key,
          responses: normalized_responses,
          score: score,
          max_score: max_score,
          submitted_at: Time.current
        )

        [ attempt, false ]
      rescue ActiveRecord::RecordNotUnique
        existing_attempt = Attempt.find_by!(submission_key: submission_key)
        reuse_attempt(existing_attempt, learner_name, normalized_responses)
      end

      def self.normalize_responses(activity_version, responses)
        snapshots = activity_version.question_snapshot
        raise InvalidResponses unless responses.is_a?(Array) && responses.length == snapshots.length

        normalized = responses.map do |response|
          raise InvalidResponses unless response.is_a?(Hash)

          question_id = response["question_id"]
          option_id = response["option_id"]
          question = snapshots.find { |item| item.fetch("id") == question_id }
          raise InvalidResponses unless question && question.fetch("options").any? { |option| option.fetch("id") == option_id }

          { "question_id" => question_id, "option_id" => option_id }
        end

        raise InvalidResponses unless normalized.map { |item| item.fetch("question_id") }.uniq.length == snapshots.length

        normalized.sort_by { |item| item.fetch("question_id") }
      end
      private_class_method :normalize_responses

      def self.reuse_attempt(attempt, learner_name, responses)
        unless attempt.learner_name == learner_name.strip && attempt.responses == responses
          raise IdempotencyConflict
        end

        [ attempt, true ]
      end
      private_class_method :reuse_attempt
    end
  end
end
