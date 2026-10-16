module Api
  module V1
    module Auth
      class GoogleCallbacksController < ApplicationController
        def create
          auth = request.env["omniauth.auth"]
          return redirect_to_frontend("google_sign_in_failed") unless verified_google_identity?(auth)

          user = User.find_or_initialize_by(google_uid: auth.uid)
          new_user = user.new_record?
          user.assign_attributes(
            email: auth.info.email.to_s.downcase,
            name: auth.info.name.to_s.presence || auth.info.email.to_s.split("@").first
          )
          return redirect_to_frontend("account_suspended") if user.persisted? && !user.active?

          user.save!

          create_user_session(user)
          if new_user && !SendWelcomeEmailJob.perform_later(user.id)
            Rails.logger.error("welcome_email_enqueue_failed user_id=#{user.id}")
          end
          redirect_to_frontend("signed_in")
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
          redirect_to_frontend("account_conflict")
        end

        def failure
          Rails.logger.warn("google_authentication_failed error=#{request.env['omniauth.error.type']}")
          redirect_to_frontend("google_sign_in_failed")
        end

        private

        def verified_google_identity?(auth)
          return false unless auth&.provider == "google_oauth2"
          return false if auth.uid.blank? || auth.info&.email.blank?

          verified = auth.extra&.raw_info&.email_verified
          [ true, "true" ].include?(verified)
        end

        def redirect_to_frontend(status)
          base = ENV["WEB_APP_URL"].presence
          base ||= "http://localhost:5173" if Rails.env.development? || Rails.env.test?
          raise "WEB_APP_URL must be configured for OAuth callbacks." if base.blank?

          uri = URI.parse(base)
          unless %w[https http].include?(uri.scheme) && uri.host && uri.userinfo.nil? &&
              (uri.scheme == "https" || Rails.env.development? || Rails.env.test?)
            raise "WEB_APP_URL must be a trusted HTTP(S) origin."
          end

          uri.path = "/"
          uri.query = URI.encode_www_form(auth: status)
          uri.fragment = nil
          redirect_to uri.to_s, status: :see_other, allow_other_host: true
        rescue URI::InvalidURIError
          raise "WEB_APP_URL is invalid."
        end
      end
    end
  end
end
