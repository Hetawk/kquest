module Assessments
  module Services
    class AdvanceGameRoomAnswer
      class InvalidAnswer < StandardError
      end

      class QuestionNotExpired < StandardError
      end

      class IdempotencyConflict < StandardError
      end

      def self.call(session:, question_id:, request_key:, option_id: nil, option_ids: nil)
        raise IdempotencyConflict unless request_key.is_a?(String) && request_key.match?(/\A[0-9a-f-]{36}\z/i)

        room = session.game_room
        raise InvalidAnswer unless room

        result = nil
        GameRoom.transaction do
          room.lock!
          session.lock!
          selected_option_ids = option_ids.is_a?(Array) ? option_ids : []
          fingerprint_option_ids = if option_ids.is_a?(Array) && option_ids.all? { |id| id.is_a?(String) }
            option_ids.sort
          else
            option_ids
          end
          multiple_select = room.activity_version.question_snapshot
            .dig(room.current_question_index, "question_type") == "multiple_select"
          answer_fingerprint = multiple_select ? fingerprint_option_ids : option_id
          fingerprint = Digest::SHA256.hexdigest([ question_id, answer_fingerprint ].to_json)
          if session.last_request_key == request_key
            raise IdempotencyConflict unless session.last_request_fingerprint == fingerprint

            result = session.last_response
            next
          end
          raise InvalidAnswer unless room.status == "active" && !session.completed?

          question = room.activity_version.question_snapshot[room.current_question_index]
          raise InvalidAnswer unless question && question.fetch("id") == question_id
          raise InvalidAnswer if session.responses.any? { |item| item["question_id"] == question_id }

          time_limit = Questions::Types::SingleChoice.live_time_limit_seconds(question)
          now = Time.current
          elapsed_seconds = [ now - room.question_started_at, 0 ].max
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

          selected_option_id = timed_out ? nil : option_id
          selected_option_ids = [] if timed_out
          answered = multiple_select ? selected_option_ids.any? : selected_option_id.present?
          award = if answered && multiple_select
            Questions::Types::MultipleSelect.score_with_speed(
              question: question,
              selected_option_ids: selected_option_ids,
              elapsed_seconds: elapsed_seconds
            )
          elsif answered
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
            "points_awarded" => award.fetch(:points_awarded),
            "speed_bonus" => award.fetch(:speed_bonus),
            "response_time_ms" => answered ? (elapsed_seconds * 1000).round : nil,
            "answered_at" => answered ? now.iso8601(6) : nil
          }
          if multiple_select
            response["option_ids"] = selected_option_ids
          else
            response["option_id"] = selected_option_id
          end
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
