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
          room.update!(
            status: "active",
            current_question_index: 0,
            round_phase: "question",
            started_at: now,
            question_started_at: now,
            question_start_times: { "0" => now.iso8601(6) }
          )
          room.play_sessions.update_all(question_started_at: now, expires_at: 1.hour.from_now, updated_at: now)
        end
        room
      end

      def self.next!(room:, question_index: nil)
        GameRoom.transaction do
          room.lock!
          raise InvalidTransition unless room.status == "active"

          snapshot = room.activity_version.question_snapshot
          now = Time.current
          if question_index
            open_question!(room, snapshot, question_index, now)
            next
          end

          case room.round_phase
          when "question"
            room.update!(round_phase: "leaderboard")
          when "leaderboard"
            closed_questions = (room.closed_question_indices || []) | [ room.current_question_index ]
            room.update!(round_phase: "answer", closed_question_indices: closed_questions)
          when "answer"
            if room.current_question_index + 1 == snapshot.length
              complete!(room, snapshot, now)
              next
            end

            open_question!(room, snapshot, room.current_question_index + 1, now)
          else
            raise InvalidTransition
          end
        end

        room
      end

      def self.open_question!(room, snapshot, target_index, now)
        raise InvalidTransition unless target_index.is_a?(Integer) &&
          target_index.between?(0, snapshot.length - 1) &&
          (target_index != room.current_question_index || room.round_phase != "question")

        start_times = room.question_start_times || {}
        unless start_times.key?(room.current_question_index.to_s)
          raise InvalidTransition unless room.question_started_at

          start_times = start_times.merge(
            room.current_question_index.to_s => room.question_started_at.iso8601(6)
          )
        end
        start_time = start_times[target_index.to_s]
        unless start_time
          start_time = now.iso8601(6)
          start_times = start_times.merge(target_index.to_s => start_time)
        end
        started_at = Time.iso8601(start_time)
        room.update!(
          current_question_index: target_index,
          round_phase: "question",
          question_started_at: started_at,
          question_start_times: start_times
        )
        room.play_sessions.where(completed_at: nil).update_all(
          current_question_index: target_index,
          question_started_at: started_at,
          expires_at: 1.hour.from_now,
          updated_at: now
        )
      end
      private_class_method :open_question!

      def self.complete!(room, snapshot, now)
        room.play_sessions.where(completed_at: nil).order(:id).lock.each do |session|
          responses = fill_unanswered(session.responses, snapshot)
          Assessments::Services::SubmitAttempt.call(
            activity_version: room.activity_version,
            learner_name: session.learner_name,
            responses: responses,
            submission_key: session.submission_key,
            game_room: room,
            started_at: room.started_at
          )
          session.update!(responses: responses, completed_at: now, question_started_at: nil)
        end
        room.update!(status: "completed", ended_at: now)
      end
      private_class_method :complete!

      def self.fill_unanswered(responses, snapshot)
        existing_question_ids = responses.map { |response| response["question_id"] }
        missing = snapshot.filter_map do |question|
          next if existing_question_ids.include?(question.fetch("id"))

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
          response
        end
        responses + missing
      end
      private_class_method :fill_unanswered
    end
  end
end
