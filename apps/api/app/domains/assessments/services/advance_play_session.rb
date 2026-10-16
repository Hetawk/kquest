module Assessments
  module Services
    class AdvancePlaySession
      class InvalidAnswer < StandardError
      end

      class QuestionNotExpired < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(session:, question_id:, request_key:, option_id: nil, option_ids: nil)
        raise IdempotencyConflict unless request_key.is_a?(String) && request_key.match?(/\A[0-9a-f-]{36}\z/i)

        result = nil
        PlaySession.transaction do
          session.lock!
          multiple_select = session.activity_version.question_snapshot
            .dig(session.current_question_index, "question_type") == "multiple_select"
          selected_option_ids = option_ids.is_a?(Array) ? option_ids : []
          fingerprint_option_ids = if option_ids.is_a?(Array) && option_ids.all? { |id| id.is_a?(String) }
            option_ids.sort
          else
            option_ids
          end
          answer_fingerprint = multiple_select ? fingerprint_option_ids : option_id
          fingerprint = Digest::SHA256.hexdigest([ question_id, answer_fingerprint ].to_json)
          if session.last_request_key == request_key
            raise IdempotencyConflict unless session.last_request_fingerprint == fingerprint

            result = session.last_response
            next
          end
          raise InvalidAnswer if session.game_room || session.completed? || session.expires_at <= Time.current

          snapshots = session.activity_version.question_snapshot
          question = snapshots[session.current_question_index]
          raise InvalidAnswer unless question && question.fetch("id") == question_id

          time_limit = question.fetch("time_limit_seconds", Questions::Types::SingleChoice::DEFAULT_TIME_LIMIT_SECONDS)
          now = Time.current
          elapsed_seconds = [ now - session.question_started_at, 0 ].max
          timed_out = time_limit.positive? && elapsed_seconds >= time_limit
          if multiple_select
            raise InvalidAnswer unless option_id.nil? && option_ids.is_a?(Array)
            raise InvalidAnswer unless selected_option_ids.all? { |id| id.is_a?(String) }
            raise InvalidAnswer unless selected_option_ids.uniq.length == selected_option_ids.length
            raise QuestionNotExpired if selected_option_ids.empty? && !timed_out
            option_ids_in_question = question.fetch("options").map { |option| option.fetch("id") }
            raise InvalidAnswer if (selected_option_ids - option_ids_in_question).any?
          else
            raise InvalidAnswer unless option_ids.nil?
            raise QuestionNotExpired if option_id.nil? && !timed_out
            if option_id && !timed_out &&
               !question.fetch("options").any? { |option| option.fetch("id") == option_id }
              raise InvalidAnswer
            end
          end

          recorded_option_id = timed_out ? nil : option_id
          recorded_option_ids = timed_out ? [] : selected_option_ids
          answered = multiple_select ? recorded_option_ids.any? : recorded_option_id.present?
          award = if answered && multiple_select
            Questions::Types::MultipleSelect.score_with_speed(
              question: question,
              selected_option_ids: recorded_option_ids,
              elapsed_seconds: elapsed_seconds
            )
          elsif answered
            Questions::Types::SingleChoice.score_with_speed(
              question: question,
              selected_option_id: recorded_option_id,
              elapsed_seconds: elapsed_seconds
            )
          else
            { points_awarded: 0, speed_bonus: 0 }
          end
          response = {
            "question_id" => question_id,
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus),
            "response_time_ms" => answered ? (elapsed_seconds * 1000).round : nil,
            "answered_at" => answered ? now.iso8601(6) : nil
          }
          if multiple_select
            response["option_ids"] = recorded_option_ids
          else
            response["option_id"] = recorded_option_id
          end
          responses = session.responses + [ response ]
          is_correct = award.fetch(:points_awarded).positive?

          if session.current_question_index + 1 == snapshots.length
            attempt, = SubmitAttempt.call(
              activity_version: session.activity_version,
              learner_name: session.learner_name,
              responses: responses,
              submission_key: session.submission_key
            )
            result = {
              "complete" => true,
              "is_correct" => is_correct,
              "timed_out" => timed_out,
              "points_awarded" => award.fetch(:points_awarded),
              "speed_bonus" => award.fetch(:speed_bonus),
              "attempt" => Activities::Serializers::PlaySerializer.result(attempt)
            }
            session.update!(
              responses: responses,
              completed_at: now,
              question_started_at: nil,
              last_request_key: request_key,
              last_request_fingerprint: fingerprint,
              last_response: result
            )
          else
            next_index = session.current_question_index + 1
            next_question = snapshots.fetch(next_index)
            next_limit = next_question.fetch(
              "time_limit_seconds",
              Questions::Types::SingleChoice::DEFAULT_TIME_LIMIT_SECONDS
            )
            result = {
              "complete" => false,
              "is_correct" => is_correct,
              "timed_out" => timed_out,
              "points_awarded" => award.fetch(:points_awarded),
              "speed_bonus" => award.fetch(:speed_bonus),
              "question_index" => next_index,
              "time_limit_seconds" => next_limit,
              "question_started_at" => now.iso8601(6),
              "server_time" => now.iso8601(6)
            }
            session.update!(
              responses: responses,
              current_question_index: next_index,
              question_started_at: now,
              last_request_key: request_key,
              last_request_fingerprint: fingerprint,
              last_response: result
            )
          end
        end

        result
      end
    end
  end
end
