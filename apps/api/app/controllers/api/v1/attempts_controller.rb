module Api
  module V1
    class AttemptsController < ApplicationController
      def create
        return unless prototype_api_only?

        activity_version = ActivityVersion.includes(:activity).find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        submission_key = request.headers["Idempotency-Key"].to_s
        unless submission_key.match?(/\A[0-9a-f-]{36}\z/i)
          return render_error(
            code: "invalid_idempotency_key",
            message: "A valid Idempotency-Key header is required.",
            status: :unprocessable_entity
          )
        end

        attributes = params.require(:attempt).permit(:learner_name, responses: [ :question_id, :option_id ])
        name = attributes[:learner_name].to_s.strip
        unless name.length.between?(1, 80)
          return render_error(
            code: "validation_failed",
            message: "The submitted data is invalid.",
            status: :unprocessable_entity,
            details: { learner_name: [ { code: "invalid_length", message: "Enter a name of 1 to 80 characters." } ] }
          )
        end

        attempt, repeated = Assessments::Services::SubmitAttempt.call(
          activity_version: activity_version,
          learner_name: name,
          responses: attributes[:responses]&.map(&:to_h),
          submission_key: submission_key
        )

        render(
          json: { data: Activities::Serializers::PlaySerializer.result(attempt) },
          status: repeated ? :ok : :created
        )
      rescue Assessments::Services::SubmitAttempt::InvalidResponses
        render_error(
          code: "invalid_responses",
          message: "Submit exactly one valid answer for each question.",
          status: :unprocessable_entity
        )
      rescue Assessments::Services::SubmitAttempt::IdempotencyConflict
        render_error(
          code: "idempotency_conflict",
          message: "This submission key was already used for different answers.",
          status: :conflict
        )
      rescue ActionController::ParameterMissing
        render_error(
          code: "validation_failed",
          message: "The submitted data is invalid.",
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
