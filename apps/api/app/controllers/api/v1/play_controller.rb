module Api
  module V1
    class PlayController < ApplicationController
      def show
        activity_version = ActivityVersion.includes(:activity).find_by(share_code: normalized_share_code)
        return render_not_found unless activity_version

        render(json: { data: Activities::Serializers::PlaySerializer.call(activity_version) })
      end

      private

      def normalized_share_code
        code = params[:share_code].to_s.upcase
        return unless ActivityVersion::CODE_REGEX.match?(code)

        code
      end
    end
  end
end
