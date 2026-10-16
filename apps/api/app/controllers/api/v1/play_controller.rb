module Api
  module V1
    class PlayController < ApplicationController
      def show
        return unless prototype_api_only?

        activity_version = ActivityVersion.includes(:activity).find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        render(json: { data: Activities::Serializers::PlaySerializer.call(activity_version) })
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
