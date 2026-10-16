module Activities
  module Serializers
    class GameRoomSerializer
      def self.call(room, participant_session: nil, include_participant_keys: false)
        snapshot = room.activity_version.question_snapshot
        current_question = room.status == "active" ? snapshot.fetch(room.current_question_index) : nil
        sessions = room.play_sessions.to_a
        standings = standings_for(room, sessions, include_participant_keys:)
        participant = if participant_session&.game_room_id == room.id
          question_id = current_question&.fetch("id")
          {
            learner_name: participant_session.learner_name,
            answered: question_id.present? &&
              participant_session.responses.any? { |response| response["question_id"] == question_id }
          }
        end

        {
          room_code: room.room_code,
          title: room.activity_version.title,
          status: room.status,
          question_index: room.current_question_index,
          question_count: snapshot.length,
          current_question: current_question && {
            id: current_question.fetch("id"),
            prompt: current_question.fetch("prompt"),
            question_type: current_question.fetch("question_type", "single_choice"),
            points: current_question.fetch("points"),
            speed_bonus_points: current_question.fetch("speed_bonus_points", current_question.fetch("points")),
            speed_scoring: current_question.fetch("speed_scoring", false),
            time_limit_seconds: Questions::Types::SingleChoice.live_time_limit_seconds(current_question),
            options: current_question.fetch("options").map { |option| { id: option.fetch("id"), text: option.fetch("text") } }
          },
          question_started_at: room.question_started_at&.iso8601(6),
          started_at: room.started_at&.iso8601(6),
          ended_at: room.ended_at&.iso8601(6),
          duration_seconds: duration_seconds(room),
          time_remaining_seconds: remaining_seconds(room, current_question),
          server_time: Time.current.iso8601(6),
          participant_count: sessions.length,
          answered_count: current_question ?
            sessions.count { |session| session.responses.any? { |response| response["question_id"] == current_question.fetch("id") } } : 0,
          participants: sessions.map do |session|
            {
              learner_name: session.learner_name,
              completed: session.completed?,
              answered: current_question.present? &&
                session.responses.any? { |response| response["question_id"] == current_question.fetch("id") }
            }
          end,
          participant: participant,
          standings: standings,
          podium: standings.first(3),
          standings_final: room.status == "completed"
        }
      end

      def self.standings_for(room, sessions, include_participant_keys:)
        attempts = Attempt.where(
          game_room_id: room.id,
          submission_key: sessions.map(&:submission_key)
        ).index_by(&:submission_key)
        sessions.map do |session|
          attempt = attempts[session.submission_key]
          responses = attempt ? attempt.responses : session.responses
          entry = {
            session_id: session.id,
            learner_name: session.learner_name,
            score: attempt ? attempt.score : responses.sum { |response| response["points_awarded"].to_i },
            max_score: attempt&.max_score,
            correct_count: responses.count { |response| response["points_awarded"].to_i.positive? },
            response_time_ms: responses.sum { |response| response["response_time_ms"].to_i }
          }
          entry[:participant_key] = Digest::SHA256.hexdigest(session.id) if include_participant_keys
          entry
        end.sort_by do |entry|
          [
            -entry.fetch(:score),
            entry.fetch(:response_time_ms),
            entry.fetch(:learner_name).downcase,
            entry.fetch(:session_id)
          ]
        end.each_with_index.map do |entry, index|
          entry.except(:session_id).merge(rank: index + 1)
        end
      end
      private_class_method :standings_for

      def self.remaining_seconds(room, question)
        return 0 unless question

        [ Questions::Types::SingleChoice.live_time_limit_seconds(question) -
          (Time.current - room.question_started_at), 0 ].max
      end
      private_class_method :remaining_seconds

      def self.duration_seconds(room)
        return unless room.started_at

        [ ((room.ended_at || Time.current) - room.started_at).floor, 0 ].max
      end
      private_class_method :duration_seconds
    end
  end
end
