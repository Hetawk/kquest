module Api
  module V1
    class PlaySessionsController < ApplicationController
      def create
        return unless prototype_api_only?

        activity_version = ActivityVersion.includes(:activity).find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        attributes = params.require(:play_session).permit(:learner_name)
        session, repeated = Assessments::Services::StartPlaySession.call(
          activity_version: activity_version,
          learner_name: attributes[:learner_name],
          start_key: request.headers["Idempotency-Key"]
        )
        question = activity_version.question_snapshot.fetch(session.current_question_index)
        time_limit = question.fetch("time_limit_seconds", Questions::Types::SingleChoice::DEFAULT_TIME_LIMIT_SECONDS)
        remaining = time_limit.positive? ?
          [ time_limit - (Time.current - session.question_started_at), 0 ].max : 0

        render(
          json: {
            data: {
              id: session.id,
              question_index: session.current_question_index,
              time_limit_seconds: time_limit,
              time_remaining_seconds: remaining,
              question_started_at: session.question_started_at.iso8601(6),
              server_time: Time.current.iso8601(6)
            }
          },
          status: repeated ? :ok : :created
        )
      rescue Assessments::Services::StartPlaySession::IdempotencyConflict
        render_error(
          code: "invalid_play_session",
          message: "Enter a valid name and use a new request key to start this quest.",
          status: :unprocessable_entity
        )
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "A learner name is required.",
          status: :unprocessable_entity
        )
      end

      private

      def normalized_share_code
        code = params[:share_code].to_s.upcase
        return unless code.match?(/\A[A-HJ-NP-Z2-9]{12}\z/)

        code
      end
    end
  end
end
