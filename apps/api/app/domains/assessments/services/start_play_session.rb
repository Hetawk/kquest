module Assessments
  module Services
    class StartPlaySession
      class IdempotencyConflict < StandardError
      end

      def self.call(activity_version:, learner_name:, start_key:)
        normalized_name = learner_name.is_a?(String) ? learner_name.strip : ""
        raise IdempotencyConflict unless start_key.is_a?(String) && start_key.match?(/\A[0-9a-f-]{36}\z/i)
        raise IdempotencyConflict unless normalized_name.length.between?(1, 80)

        session = PlaySession.find_by(start_key: start_key)
        return reuse_session(session, activity_version, normalized_name) if session

        session = PlaySession.create!(
          activity_version: activity_version,
          learner_name: normalized_name,
          start_key: start_key,
          submission_key: SecureRandom.uuid,
          current_question_index: 0,
          responses: [],
          question_started_at: Time.current,
          expires_at: 1.hour.from_now
        )

        [ session, false ]
      rescue ActiveRecord::RecordNotUnique
        session = PlaySession.find_by!(start_key: start_key)
        reuse_session(session, activity_version, normalized_name)
      end

      def self.reuse_session(session, activity_version, learner_name)
        unless session.activity_version_id == activity_version.id &&
               session.learner_name == learner_name &&
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
