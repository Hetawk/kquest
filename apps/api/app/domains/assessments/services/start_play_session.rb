module Assessments
  module Services
    class StartPlaySession
      class IdempotencyConflict < StandardError
      end

      def self.call(activity_version:, learner_name:, start_key:, game_room: nil)
        normalized_name = learner_name.is_a?(String) ? learner_name.strip : ""
        raise IdempotencyConflict unless start_key.is_a?(String) && start_key.match?(/\A[0-9a-f-]{36}\z/i)
        raise IdempotencyConflict unless normalized_name.length.between?(1, 80)

        session = PlaySession.find_by(start_key: start_key)
        return reuse_session(session, activity_version, normalized_name, game_room) if session

        attributes = {
          activity_version: activity_version,
          game_room: game_room,
          learner_name: normalized_name,
          start_key: start_key,
          submission_key: SecureRandom.uuid,
          current_question_index: 0,
          responses: [],
          question_started_at: game_room ? nil : Time.current,
          expires_at: 1.hour.from_now
        }
        if game_room
          game_room.with_lock do
            raise IdempotencyConflict unless game_room.status == "waiting"

            session = PlaySession.create!(attributes)
          end
        else
          session = PlaySession.create!(attributes)
        end

        [ session, false ]
      rescue ActiveRecord::RecordNotUnique
        session = PlaySession.find_by!(start_key: start_key)
        reuse_session(session, activity_version, normalized_name, game_room)
      end

      def self.reuse_session(session, activity_version, learner_name, game_room)
        unless session.activity_version_id == activity_version.id &&
               session.learner_name == learner_name &&
               session.game_room_id == game_room&.id &&
               !session.completed? &&
               session.expires_at > Time.current
          raise IdempotencyConflict
        end

        [ session, true ]
      end
      private_class_method :reuse_session
    end
  end
end
