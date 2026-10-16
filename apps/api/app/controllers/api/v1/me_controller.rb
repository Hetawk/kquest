module Api
  module V1
    class MeController < ApplicationController
      before_action :require_current_user

      def show
        return unless current_user

        render json: {
          data: {
            id: current_user.id,
            email: current_user.email,
            name: current_user.name
          }
        }
      end
    end
  end
end
