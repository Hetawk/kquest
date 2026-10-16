class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection

  protect_from_forgery with: :exception
  rescue_from ActionController::InvalidAuthenticityToken do
    render_error(
      code: "invalid_csrf_token",
      message: "Refresh the page and try again.",
      status: :forbidden
    )
  end

  private

  def current_user
    return @current_user if defined?(@current_user)

    token = cookies.encrypted[:kquest_session]
    if token.present?
      session_record = UserSession.active.includes(:user).find_by(
        token_digest: Digest::SHA256.hexdigest(token)
      )
      @current_user = session_record&.user if session_record&.user&.active?
      @current_session = session_record if @current_user
    end
    @current_user
  end

  def current_session
    current_user
    @current_session
  end

  def require_current_user
    return if current_user

    render_error(
      code: "authentication_required",
      message: "Sign in to continue.",
      status: :unauthorized
    )
  end

  def create_user_session(user)
    token = SecureRandom.urlsafe_base64(32)
    user.user_sessions.create!(
      token_digest: Digest::SHA256.hexdigest(token),
      expires_at: 7.days.from_now
    )
    cookies.encrypted[:kquest_session] = {
      value: token,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax,
      expires: 7.days.from_now
    }
  end

  def clear_user_session
    current_session&.revoke!
    cookies.delete(
      :kquest_session,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    )
  end

  def render_error(code:, message:, status:, details: {})
    render(
      json: {
        error: {
          code: code,
          message: message,
          details: details
        }
      },
      status: status
    )
  end

  def render_validation_error(record)
    details = record.errors.group_by_attribute.transform_values do |errors|
      errors.map do |error|
        { code: error.type.to_s, message: error.message }
      end
    end

    render_error(
      code: "validation_failed",
      message: "The submitted data is invalid.",
      status: :unprocessable_entity,
      details: details
    )
  end

  def render_not_found
    render_error(
      code: "not_found",
      message: "The requested resource was not found.",
      status: :not_found
    )
  end
end
