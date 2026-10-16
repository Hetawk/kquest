module Assessments
  module Services
    class AdvanceGameRoomAnswer
      class InvalidAnswer < StandardError
      end

      class QuestionNotExpired < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(session:, question_id:, option_id:, request_key:)
        raise IdempotencyConflict unless request_key.is_a?(String) && request_key.match?(/\A[0-9a-f-]{36}\z/i)

        room = session.game_room
        raise InvalidAnswer unless room

        result = nil
        GameRoom.transaction do
          room.lock!
          session.lock!
          fingerprint = Digest::SHA256.hexdigest([ question_id, option_id ].to_json)
          if session.last_request_key == request_key
            raise IdempotencyConflict unless session.last_request_fingerprint == fingerprint

            result = session.last_response
            next
          end
          raise InvalidAnswer unless room.status == "active" && !session.completed?

          question = room.activity_version.question_snapshot[room.current_question_index]
          raise InvalidAnswer unless question && question.fetch("id") == question_id
          raise InvalidAnswer if session.responses.any? { |item| item["question_id"] == question_id }

          time_limit = question.fetch("time_limit_seconds", Questions::Types::SingleChoice::DEFAULT_TIME_LIMIT_SECONDS)
          now = Time.current
          elapsed_seconds = [ now - room.question_started_at, 0 ].max
          timed_out = time_limit.positive? && elapsed_seconds >= time_limit
          raise QuestionNotExpired if option_id.nil? && !timed_out

          if option_id && !timed_out &&
             !question.fetch("options").any? { |option| option.fetch("id") == option_id }
            raise InvalidAnswer
          end

          selected_option_id = timed_out ? nil : option_id
          award = if selected_option_id
            Questions::Types::SingleChoice.score_with_speed(
              question: question,
              selected_option_id: selected_option_id,
              elapsed_seconds: elapsed_seconds
            )
          else
            { points_awarded: 0, speed_bonus: 0 }
          end
          response = {
            "question_id" => question_id,
            "option_id" => selected_option_id,
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus),
            "response_time_ms" => selected_option_id ? (elapsed_seconds * 1000).round : nil,
            "answered_at" => selected_option_id ? now.iso8601(6) : nil
          }
          result = {
            "complete" => false,
            "is_correct" => award.fetch(:points_awarded).positive?,
            "timed_out" => timed_out,
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus),
            "question_index" => room.current_question_index
          }
          session.update!(
            responses: session.responses + [ response ],
            last_request_key: request_key,
            last_request_fingerprint: fingerprint,
            last_response: result
          )
        end

        result
      end
    end
  end
end
