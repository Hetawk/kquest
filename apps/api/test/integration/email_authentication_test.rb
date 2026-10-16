require "test_helper"

class EmailAuthenticationTest < ActionDispatch::IntegrationTest
  FakeResponse = Struct.new(:body, :code) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  FakeHttp = Struct.new(:response) do
    attr_reader :last_request

    def request(request)
      @last_request = request
      response
    end
  end

  setup do
    @previous_key = ENV["EKDSEND_API_KEY"]
    ENV["EKDSEND_API_KEY"] = "test-mail-key"
    @fake_http = FakeHttp.new(
      FakeResponse.new({ success: true, messageId: "auth-message" }.to_json, "200")
    )
  end

  teardown do
    ENV["EKDSEND_API_KEY"] = @previous_key
  end

  test "registration verifies the email before creating a session and supports password sign-in" do
    with_fake_http do
      post "/api/v1/auth/email/register",
        params: {
          email: "  educator@example.test ",
          name: "Educator",
          password: "a-secure-password",
          password_confirmation: "a-secure-password"
        },
        headers: csrf_headers,
        as: :json

      assert_response :created
      assert_equal true, response.parsed_body.dig("data", "verification_required")
      user = User.find_by!(email: "educator@example.test")
      assert_nil user.email_verified_at
      challenge = AuthChallenge.find_by!(user:, purpose: "email_verification")
      code = code_from_email
      refute_equal code, challenge.code_digest
      assert_equal 0, user.user_sessions.count

      post "/api/v1/auth/email/verify",
        params: { email: user.email, code: },
        headers: csrf_headers,
        as: :json

      assert_response :success
      assert user.reload.email_verified_at
      assert_equal user.id, response.parsed_body.dig("data", "id")
      assert_equal 1, user.user_sessions.active.count
      assert_enqueued_with(job: SendWelcomeEmailJob, args: [ user.id ])

      delete "/api/v1/auth/session", headers: csrf_headers, as: :json
      assert_response :no_content

      post "/api/v1/auth/email/login",
        params: { email: user.email, password: "a-secure-password" },
        headers: csrf_headers,
        as: :json

      assert_response :success
      assert_equal user.id, response.parsed_body.dig("data", "id")
    end
  end

  test "unverified accounts cannot sign in and can request another code" do
    user = User.create!(
      email: "pending@example.test",
      name: "Pending",
      password: "a-secure-password"
    )

    post "/api/v1/auth/email/login",
      params: { email: user.email, password: "a-secure-password" },
      headers: csrf_headers,
      as: :json

    assert_response :forbidden
    assert_equal "email_unverified", response.parsed_body.dig("error", "code")

    with_fake_http do
      post "/api/v1/auth/email/resend-verification",
        params: { email: user.email },
        headers: csrf_headers,
        as: :json
      assert_response :success
      assert_match(/\d{6}/, JSON.parse(@fake_http.last_request.body).fetch("text"))
    end
  end

  test "password reset codes are single-use and replace the password" do
    user = User.create!(
      email: "reset@example.test",
      name: "Reset User",
      password: "an-old-password",
      email_verified_at: Time.current
    )
    prior_session = user.user_sessions.create!(
      token_digest: Digest::SHA256.hexdigest(SecureRandom.hex),
      expires_at: 7.days.from_now
    )

    with_fake_http do
      post "/api/v1/auth/password/forgot",
        params: { email: user.email },
        headers: csrf_headers,
        as: :json
      assert_response :success
      assert_equal(
        "If an email/password account exists for that address, a reset code is on its way.",
        response.parsed_body.dig("data", "message")
      )
      code = code_from_email

      post "/api/v1/auth/password/reset",
        params: {
          email: user.email,
          code:,
          password: "a-new-secure-password",
          password_confirmation: "a-new-secure-password"
        },
        headers: csrf_headers,
        as: :json

      assert_response :success
      assert user.reload.authenticate("a-new-secure-password")
      refute user.authenticate("an-old-password")
      assert_equal 1, user.user_sessions.active.count
      assert prior_session.reload.revoked_at

      post "/api/v1/auth/password/reset",
        params: {
          email: user.email,
          code:,
          password: "another-secure-password",
          password_confirmation: "another-secure-password"
        },
        headers: csrf_headers,
        as: :json
      assert_response :unprocessable_entity
    end
  end

  test "password reset response is the same when the email is not registered" do
    post "/api/v1/auth/password/forgot",
      params: { email: "unknown@example.test" },
      headers: csrf_headers,
      as: :json

    assert_response :success
    assert_equal(
      "If an email/password account exists for that address, a reset code is on its way.",
      response.parsed_body.dig("data", "message")
    )
    assert_equal 0, AuthChallenge.count
  end

  test "password reset does not activate unverified or Google-only accounts" do
    unverified_user = User.create!(
      email: "unverified@example.test",
      name: "Unverified",
      password: "a-secure-password"
    )
    google_user = User.create!(
      email: "google@example.test",
      name: "Google User",
      google_uid: "google-only-user"
    )

    [ unverified_user, google_user ].each do |user|
      post "/api/v1/auth/password/forgot",
        params: { email: user.email },
        headers: csrf_headers,
        as: :json
      assert_response :success
      assert_equal 0, AuthChallenge.where(email: user.email, purpose: "password_reset").count
    end
  end

  test "verification codes expire and reject invalid codes" do
    user = User.create!(
      email: "expired@example.test",
      name: "Expired",
      password: "a-secure-password"
    )
    challenge, = AuthChallenge.issue!(
      email: user.email,
      purpose: "email_verification",
      user:
    )
    challenge.update!(expires_at: 1.minute.ago)

    post "/api/v1/auth/email/verify",
      params: { email: user.email, code: "000000" },
      headers: csrf_headers,
      as: :json

    assert_response :unprocessable_entity
    assert_nil user.reload.email_verified_at
  end

  test "verification codes stop accepting guesses after five attempts" do
    user = User.create!(
      email: "attempts@example.test",
      name: "Attempts",
      password: "a-secure-password"
    )
    challenge, valid_code = AuthChallenge.issue!(
      email: user.email,
      purpose: "email_verification",
      user:
    )
    invalid_code = valid_code == "000000" ? "000001" : "000000"

    5.times { refute challenge.consume_if_valid!(invalid_code) }
    refute challenge.consume_if_valid!(valid_code)
    assert_equal 5, challenge.reload.attempts
  end

  test "registration requires a valid email and a strong confirmed password" do
    post "/api/v1/auth/email/register",
      params: {
        email: "not-an-email",
        name: "Educator",
        password: "short",
        password_confirmation: "short"
      },
      headers: csrf_headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal 0, User.count

    multibyte_password = "é" * 37
    post "/api/v1/auth/email/register",
      params: {
        email: "bytes@example.test",
        name: "Educator",
        password: multibyte_password,
        password_confirmation: multibyte_password
      },
      headers: csrf_headers,
      as: :json

    assert_response :unprocessable_entity
    assert_equal 0, User.count
  end

  test "email sign-in is rate limited after ten failures" do
    cache = ActiveSupport::Cache::MemoryStore.new
    original_cache = Rails.method(:cache)
    Rails.singleton_class.define_method(:cache) { cache }
    begin
      10.times do
        post "/api/v1/auth/email/login",
          params: { email: "unknown@example.test", password: "a-secure-password" },
          headers: csrf_headers,
          as: :json
        assert_response :unauthorized
      end

      post "/api/v1/auth/email/login",
        params: { email: "unknown@example.test", password: "a-secure-password" },
        headers: csrf_headers,
        as: :json

      assert_response :too_many_requests
    ensure
      Rails.singleton_class.define_method(:cache, original_cache)
    end
  end

  private

  def csrf_headers
    get "/api/v1/auth/csrf", as: :json
    { "X-CSRF-Token" => response.parsed_body.dig("data", "token") }
  end

  def code_from_email
    text = JSON.parse(@fake_http.last_request.body).fetch("text")
    text.match(/\b(\d{6})\b/).captures.fetch(0)
  end

  def with_fake_http
    original_start = Net::HTTP.method(:start)
    fake_http = @fake_http
    Net::HTTP.singleton_class.define_method(:start) do |*_arguments, **_keywords, &block|
      block.call(fake_http)
    end
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:start, original_start)
  end
end
