module Api
  module V1
    class PlayAnswersController < ApplicationController
      def create
        return unless prototype_api_only?

        activity_version = ActivityVersion.includes(:activity).find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        session = activity_version.play_sessions.find_by(id: params[:session_id])
        return render_not_found unless session

        attributes = params.require(:answer).permit(:question_id, :option_id)
        result = Assessments::Services::AdvancePlaySession.call(
          session: session,
          question_id: attributes[:question_id],
          option_id: attributes[:option_id],
          request_key: request.headers["Idempotency-Key"]
        )
        render(json: { data: result })
      rescue Assessments::Services::AdvancePlaySession::QuestionNotExpired
        render_error(
          code: "question_not_expired",
          message: "Choose an answer before time runs out.",
          status: :conflict
        )
      rescue Assessments::Services::AdvancePlaySession::IdempotencyConflict
        render_error(
          code: "idempotency_conflict",
          message: "This answer request key was already used for a different response.",
          status: :conflict
        )
      rescue Assessments::Services::AdvancePlaySession::InvalidAnswer
        render_error(
          code: "invalid_answer",
          message: "This question can no longer accept that answer.",
          status: :unprocessable_entity
        )
      rescue Assessments::Services::SubmitAttempt::InvalidResponses
        render_error(
          code: "invalid_answer",
          message: "The answer does not match the current question.",
          status: :unprocessable_entity
        )
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "A question identifier is required.",
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
