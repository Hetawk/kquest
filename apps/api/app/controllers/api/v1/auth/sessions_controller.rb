module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        def destroy
          clear_user_session
          head :no_content
        end
      end
    end
  end
end
