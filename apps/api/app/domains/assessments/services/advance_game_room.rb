module Assessments
  module Services
    class AdvanceGameRoom
      class InvalidTransition < StandardError
      end

      def self.start!(room:)
        GameRoom.transaction do
          room.lock!
          raise InvalidTransition unless room.status == "waiting" && room.play_sessions.exists?

          now = Time.current
          room.update!(status: "active", current_question_index: 0, question_started_at: now)
          room.play_sessions.update_all(question_started_at: now, expires_at: 1.hour.from_now, updated_at: now)
        end
        room
      end

      def self.next!(room:)
        GameRoom.transaction do
          room.lock!
          raise InvalidTransition unless room.status == "active"

          snapshot = room.activity_version.question_snapshot
          question = snapshot.fetch(room.current_question_index)
          now = Time.current
          room.play_sessions.where(completed_at: nil).order(:id).lock.each do |session|
            next if session.responses.any? { |response| response["question_id"] == question.fetch("id") }

            response = {
              "question_id" => question.fetch("id"),
              "points_awarded" => 0,
              "speed_bonus" => 0,
              "response_time_ms" => nil,
              "answered_at" => nil
            }
            if question.fetch("question_type", "single_choice") == "multiple_select"
              response["option_ids"] = []
            else
              response["option_id"] = nil
            end
            session.update!(responses: session.responses + [ response ], updated_at: now)
          end

          if room.current_question_index + 1 == snapshot.length
            room.play_sessions.where(completed_at: nil).order(:id).lock.each do |session|
              Assessments::Services::SubmitAttempt.call(
                activity_version: room.activity_version,
                learner_name: session.learner_name,
                responses: session.responses,
                submission_key: session.submission_key,
                game_room: room
              )
              session.update!(completed_at: now, question_started_at: nil)
            end
            room.update!(status: "completed", ended_at: now)
          else
            next_index = room.current_question_index + 1
            room.update!(
              current_question_index: next_index,
              question_started_at: now
            )
            room.play_sessions.where(completed_at: nil).update_all(
              current_question_index: next_index,
              question_started_at: now,
              expires_at: 1.hour.from_now,
              updated_at: now
            )
          end
        end

        room
      end
    end
  end
end
