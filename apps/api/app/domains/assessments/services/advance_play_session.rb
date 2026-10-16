module Assessments
  module Services
    class AdvancePlaySession
      class InvalidAnswer < StandardError
      end

      class QuestionNotExpired < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(session:, question_id:, option_id:, request_key:)
        raise IdempotencyConflict unless request_key.is_a?(String) && request_key.match?(/\A[0-9a-f-]{36}\z/i)

        result = nil
        PlaySession.transaction do
          session.lock!
          fingerprint = Digest::SHA256.hexdigest([ question_id, option_id ].to_json)
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
          raise QuestionNotExpired if option_id.nil? && !timed_out

          if option_id && !timed_out &&
             !question.fetch("options").any? { |option| option.fetch("id") == option_id }
            raise InvalidAnswer
          end

          recorded_option_id = timed_out ? nil : option_id
          award = if recorded_option_id
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
            "option_id" => recorded_option_id,
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus),
            "response_time_ms" => recorded_option_id ? (elapsed_seconds * 1000).round : nil,
            "answered_at" => recorded_option_id ? now.iso8601(6) : nil
          }
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
