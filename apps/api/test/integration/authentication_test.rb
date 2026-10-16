require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @previous_csrf_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = google_identity
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_csrf_setting
    OmniAuth.config.test_mode = @previous_test_mode
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "Google sign-in creates a revocable session and queues one welcome email" do
    sign_in_with_google
    user = User.find_by!(google_uid: "google-subject-1")

    assert_response :see_other
    assert_redirected_to "http://localhost:5173/?auth=signed_in"
    assert_enqueued_with(job: SendWelcomeEmailJob, args: [ user.id ])

    get "/api/v1/me", as: :json

    assert_response :success
    assert_equal user.id, response.parsed_body.dig("data", "id")

    delete "/api/v1/auth/session", headers: { "X-CSRF-Token" => fetch_csrf_token }, as: :json
    assert_response :no_content
    assert_equal 1, user.user_sessions.where.not(revoked_at: nil).count

    get "/api/v1/me", as: :json

    assert_response :unauthorized
  end

  test "Google accounts with unverified email addresses cannot sign in" do
    OmniAuth.config.mock_auth[:google_oauth2] = google_identity(email_verified: false)
    sign_in_with_google

    assert_response :see_other
    assert_redirected_to "http://localhost:5173/?auth=google_sign_in_failed"
    assert_equal 0, User.count
  end

  test "an email already attached to another Google identity is not silently linked" do
    User.create!(google_uid: "existing-google-subject", email: "educator@example.test", name: "Existing")
    sign_in_with_google

    assert_response :see_other
    assert_redirected_to "http://localhost:5173/?auth=account_conflict"
    assert_equal 1, User.count
  end

  test "OAuth sign-in requires the Rails CSRF token" do
    post "/api/v1/auth/google_oauth2", as: :json

    assert_response :found
    follow_redirect!
    assert_response :see_other
    assert_redirected_to "http://localhost:5173/?auth=google_sign_in_failed"
    assert_equal 0, User.count
  end

  test "the current-user endpoint rejects requests without a valid session" do
    get "/api/v1/me", as: :json

    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
  end

  test "the creator quest dashboard requires a signed-in user" do
    get "/api/v1/activities", as: :json

    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
  end

  private

  def sign_in_with_google
    token = fetch_csrf_token
    post "/api/v1/auth/google_oauth2",
      params: { authenticity_token: token },
      headers: { "HTTP_REFERER" => "http://www.example.com/" }
    follow_redirect! if response.redirect?
  end

  def fetch_csrf_token
    get "/api/v1/auth/csrf", as: :json
    response.parsed_body.dig("data", "token")
  end

  def google_identity(email_verified: true)
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-subject-1",
      info: {
        email: "educator@example.test",
        name: "Test Educator"
      },
      extra: {
        raw_info: {
          email_verified: email_verified
        }
      }
    )
  end
end
