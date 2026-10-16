module Api
  module V1
    class HealthController < ApplicationController
      def show
        render json: { data: { status: "ok", api_version: "v1" } }
      end
    end
  end
end
