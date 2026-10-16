module Api
  module V1
    module Auth
      class EmailController < ApplicationController
        GENERIC_RESET_MESSAGE = "If an email/password account exists for that address, a reset code is on its way."
        GENERIC_RESEND_MESSAGE = "If the address needs verification, a code is on its way."

        def register
          email = normalized_email
          password = params[:password].to_s
          confirmation = params[:password_confirmation].to_s
          name = params[:name].to_s.strip

          unless valid_email?(email) && name.present? && name.length <= 160 &&
              valid_password?(password) && password == confirmation
            return render_error(
              code: "invalid_registration",
              message: "Enter a valid email, your name, and matching passwords of at least 12 characters.",
              status: :unprocessable_entity
            )
          end

          if User.exists?(email:)
            return render_error(
              code: "account_exists",
              message: "An account already uses this email. Sign in or reset your password.",
              status: :conflict
            )
          end

          user = User.create!(email:, name:, password:)
          challenge, code = AuthChallenge.issue!(email:, purpose: "email_verification", user:)
          deliver_code!(challenge, code, name:)
          render json: { data: { verification_required: true, email: } }, status: :created
        rescue AuthChallenge::RateLimited
          rate_limited
        rescue AuthChallenge::ResendTooSoon
          resend_too_soon
        rescue Integrations::EkdSend::Client::DeliveryError => error
          Rails.logger.error("auth_email_delivery_failed purpose=email_verification error=#{error.class}")
          render_error(
            code: "email_delivery_unavailable",
            message: "We could not send your verification code. Please try again shortly.",
            status: :service_unavailable
          )
        rescue ActiveRecord::RecordNotUnique
          render_error(
            code: "account_exists",
            message: "An account already uses this email. Sign in or reset your password.",
            status: :conflict
          )
        end

        def login
          email = normalized_email
          email_limit_key, ip_limit_key = login_rate_limit_keys(email)
          if Rails.cache.read(email_limit_key).to_i >= 10 ||
              Rails.cache.read(ip_limit_key).to_i >= 50
            return render_error(
              code: "too_many_attempts",
              message: "Too many sign-in attempts. Wait 15 minutes and try again.",
              status: :too_many_requests
            )
          end

          user = User.find_by(email:)
          submitted_password = params[:password].to_s
          unless valid_password?(submitted_password) && user&.authenticate(submitted_password)
            Rails.cache.increment(email_limit_key, 1, expires_in: 15.minutes)
            Rails.cache.increment(ip_limit_key, 1, expires_in: 15.minutes)
            return render_error(
              code: "invalid_credentials",
              message: "The email or password is incorrect.",
              status: :unauthorized
            )
          end

          unless user.active?
            return render_error(
              code: "account_suspended",
              message: "This account is not currently active.",
              status: :forbidden
            )
          end

          unless user.email_verified_at?
            return render_error(
              code: "email_unverified",
              message: "Verify your email address before signing in.",
              status: :forbidden
            )
          end

          Rails.cache.delete(email_limit_key)
          create_user_session(user)
          render json: { data: user_payload(user) }
        end

        def verify
          email = normalized_email
          code = normalized_code
          challenge = AuthChallenge.active.where(email:, purpose: "email_verification")
            .order(created_at: :desc).first
          unless valid_code?(code) && challenge&.consume_if_valid!(code)
            return invalid_code
          end

          user = challenge.user || User.find_by(email:)
          return invalid_code unless user&.active?

          newly_verified = !user.email_verified_at?
          user.update!(email_verified_at: Time.current) if newly_verified
          create_user_session(user)
          if newly_verified && !SendWelcomeEmailJob.perform_later(user.id)
            Rails.logger.error("welcome_email_enqueue_failed user_id=#{user.id}")
          end
          render json: { data: user_payload(user) }
        end

        def resend_verification
          email = normalized_email
          user = User.find_by(email:)
          if user && !user.email_verified_at? && user.password_digest.present?
            challenge, code = AuthChallenge.issue!(email:, purpose: "email_verification", user:)
            deliver_code!(challenge, code, name: user.name)
          end
          render json: { data: { message: GENERIC_RESEND_MESSAGE } }
        rescue AuthChallenge::RateLimited
          rate_limited
        rescue AuthChallenge::ResendTooSoon
          resend_too_soon
        rescue Integrations::EkdSend::Client::DeliveryError => error
          Rails.logger.error("auth_email_delivery_failed purpose=email_verification error=#{error.class}")
          email_delivery_unavailable
        end

        def forgot_password
          email = normalized_email
          user = User.find_by(email:)
          if user&.active? && user.password_digest.present? && user.email_verified_at?
            challenge, code = AuthChallenge.issue!(email:, purpose: "password_reset", user:)
            deliver_code!(challenge, code, name: user.name, reset: true)
          end
          render json: { data: { message: GENERIC_RESET_MESSAGE } }
        rescue AuthChallenge::RateLimited
          rate_limited
        rescue AuthChallenge::ResendTooSoon
          resend_too_soon
        rescue Integrations::EkdSend::Client::DeliveryError => error
          Rails.logger.error("auth_email_delivery_failed purpose=password_reset error=#{error.class}")
          email_delivery_unavailable
        end

        def reset_password
          email = normalized_email
          code = normalized_code
          password = params[:password].to_s
          confirmation = params[:password_confirmation].to_s
          unless valid_password?(password) && password == confirmation
            return render_error(
              code: "invalid_password",
              message: "Choose a password with at least 12 characters and no more than 72 bytes.",
              status: :unprocessable_entity
            )
          end

          challenge = AuthChallenge.active.find_by(email:, purpose: "password_reset")
          unless valid_code?(code) && challenge&.consume_if_valid!(code)
            return invalid_code
          end

          user = challenge.user
          return invalid_code unless user&.active?

          user.update!(password:, email_verified_at: user.email_verified_at || Time.current)
          user.user_sessions.active.update_all(revoked_at: Time.current)
          create_user_session(user)
          render json: { data: user_payload(user) }
        end

        private

        def normalized_email
          params[:email].to_s.strip.downcase
        end

        def normalized_code
          params[:code].to_s.gsub(/[\p{Space}-]/, "")
        end

        def valid_email?(email)
          email.length <= 320 && URI::MailTo::EMAIL_REGEXP.match?(email)
        end

        def valid_password?(password)
          password.length >= 12 && password.bytesize <= 72
        end

        def valid_code?(code)
          code.match?(/\A\d{6}\z/)
        end

        def invalid_code
          render_error(
            code: "invalid_or_expired_code",
            message: "That code is invalid or expired. Request a new code and try again.",
            status: :unprocessable_entity
          )
        end

        def deliver_code!(challenge, code, name:, reset: false)
          escaped_name = ERB::Util.html_escape(name.to_s)
          purpose_text = reset ? "reset your KINGDOM Quest password" : "verify your KINGDOM Quest email"
          Integrations::EkdSend::Client.new.send_email(
            to: challenge.email,
            subject: reset ? "Your KINGDOM Quest password reset code" : "Verify your KINGDOM Quest email",
            html: "<p>Hello #{escaped_name},</p><p>Use this code to #{purpose_text}:</p><p style=\"font-size:28px;font-weight:bold;letter-spacing:8px\">#{code}</p><p>This code expires in 10 minutes. If you did not request it, you can ignore this message.</p>",
            text: "Hello #{name},\n\nYour KINGDOM Quest code to #{purpose_text} is #{code}.\nIt expires in 10 minutes. If you did not request it, you can ignore this message."
          )
        rescue Integrations::EkdSend::Client::DeliveryError
          challenge.destroy!
          raise
        end

        def user_payload(user)
          { id: user.id, email: user.email, name: user.name }
        end

        def login_rate_limit_keys(email)
          email_digest = Digest::SHA256.hexdigest(email)
          ip_digest = Digest::SHA256.hexdigest(request.remote_ip.to_s)
          [ "kquest:auth:login:email:#{email_digest}", "kquest:auth:login:ip:#{ip_digest}" ]
        end

        def rate_limited
          render_error(
            code: "too_many_requests",
            message: "Too many code requests. Try again later.",
            status: :too_many_requests
          )
        end

        def resend_too_soon
          render_error(
            code: "resend_too_soon",
            message: "Please wait a minute before requesting another code.",
            status: :too_many_requests
          )
        end

        def email_delivery_unavailable
          render_error(
            code: "email_delivery_unavailable",
            message: "We could not send your code. Please try again shortly.",
            status: :service_unavailable
          )
        end
      end
    end
  end
end
