module Assessments
  module Services
    class SubmitAttempt
      class InvalidResponses < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(activity_version:, learner_name:, responses:, submission_key:, game_room: nil, started_at: nil)
        normalized_responses = normalize_responses(activity_version, responses, speed_scoring: game_room.present?)
        raise InvalidResponses unless learner_name.is_a?(String) && learner_name.strip.length.between?(1, 80)

        existing_attempt = Attempt.find_by(submission_key: submission_key)
        return reuse_attempt(existing_attempt, learner_name, normalized_responses) if existing_attempt

        snapshots = activity_version.question_snapshot
        score = snapshots.sum do |question|
          response = normalized_responses.find { |item| item.fetch("question_id") == question.fetch("id") }
          response.fetch("points_awarded")
        end
        max_score = snapshots.sum do |question|
          if game_room
            Questions::Types::SingleChoice.maximum_points(question)
          else
            question.fetch("points")
          end
        end

        submitted_at = Time.current
        attempt = Attempt.create!(
          activity_version: activity_version,
          game_room: game_room,
          learner_name: learner_name.strip,
          submission_key: submission_key,
          responses: normalized_responses,
          score: score,
          max_score: max_score,
          total_response_time_ms: normalized_responses.sum { |response| response["response_time_ms"].to_i },
          started_at: started_at,
          submitted_at: submitted_at
        )

        [ attempt, false ]
      rescue ActiveRecord::RecordNotUnique
        existing_attempt = Attempt.find_by!(submission_key: submission_key)
        reuse_attempt(existing_attempt, learner_name, normalized_responses)
      end

      def self.normalize_responses(activity_version, responses, speed_scoring:)
        snapshots = activity_version.question_snapshot
        raise InvalidResponses unless responses.is_a?(Array) && responses.length == snapshots.length

        normalized = responses.map do |response|
          raise InvalidResponses unless response.is_a?(Hash)

          question_id = response["question_id"]
          option_id = response["option_id"]
          option_ids = response["option_ids"]
          question = snapshots.find { |item| item.fetch("id") == question_id }
          raise InvalidResponses unless question
          multiple_select = question.fetch("question_type", "single_choice") == "multiple_select"
          available_option_ids = question.fetch("options").map { |option| option.fetch("id") }
          if multiple_select
            raise InvalidResponses unless option_id.nil? && option_ids.is_a?(Array)
            raise InvalidResponses unless option_ids.all? { |id| id.is_a?(String) }
            raise InvalidResponses unless option_ids.uniq.length == option_ids.length
            raise InvalidResponses if (option_ids - available_option_ids).any?
          else
            raise InvalidResponses unless option_ids.nil?
            raise InvalidResponses if option_id && !available_option_ids.include?(option_id)
          end

          response_time_ms = response["response_time_ms"]
          if response_time_ms && (!response_time_ms.is_a?(Integer) || response_time_ms.negative?)
            raise InvalidResponses
          end
          selected = multiple_select ? option_ids : option_id
          answered = multiple_select ? option_ids.any? : option_id.present?
          award = if speed_scoring && answered && response_time_ms && multiple_select
            Questions::Types::MultipleSelect.score_with_speed(
              question: question,
              selected_option_ids: option_ids,
              elapsed_seconds: response_time_ms / 1000.0
            )
          elsif speed_scoring && answered && response_time_ms
            Questions::Types::SingleChoice.score_with_speed(
              question: question,
              selected_option_id: option_id,
              elapsed_seconds: response_time_ms / 1000.0
            )
          elsif multiple_select
            {
              points_awarded: Questions::Types::MultipleSelect.score(
                question: question,
                selected_option_ids: option_ids
              ),
              speed_bonus: 0
            }
          else
            {
              points_awarded: Questions::Types::SingleChoice.score(
                question: question,
                selected_option_id: option_id
              ),
              speed_bonus: 0
            }
          end
          normalized_response = {
            "question_id" => question_id,
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus)
          }
          if multiple_select
            normalized_response["option_ids"] = selected.sort
          else
            normalized_response["option_id"] = selected
          end
          normalized_response["response_time_ms"] = response_time_ms if response_time_ms
          normalized_response["answered_at"] = response["answered_at"] if response["answered_at"]
          normalized_response
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
