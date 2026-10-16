require "test_helper"

class LearningJourneyTest < ActionDispatch::IntegrationTest
  setup do
    @previous_csrf_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "test-google-user",
      info: { email: "educator@example.test", name: "Educator" },
      extra: { raw_info: { email_verified: true } }
    )
    get "/api/v1/auth/csrf", as: :json
    post "/api/v1/auth/google_oauth2",
      params: { authenticity_token: response.parsed_body.dig("data", "token") }
    follow_redirect! if response.redirect?
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_csrf_setting
    OmniAuth.config.test_mode = @previous_test_mode
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  def create_activity(questions: [ question_definition ])
    post "/api/v1/activities",
      params: {
        activity: {
          title: "The Solar System Sprint",
          description: "A quick trip through our cosmic neighborhood.",
          questions: questions
        }
      },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :created
    response.parsed_body.fetch("data").fetch("id")
  end

  def question_definition(prompt: "Which planet is known as the Red Planet?", correct_index: 0, time_limit_seconds: 30)
    options = [
      { id: "10101010-1010-4101-8101-101010101001", text: "Mars" },
      { id: "10101010-1010-4101-8101-101010101002", text: "Venus" },
      { id: "10101010-1010-4101-8101-101010101003", text: "Jupiter" }
    ]

    {
      prompt: prompt,
      options: options,
      correct_option_id: options.fetch(correct_index).fetch(:id),
      points: 100,
      time_limit_seconds: time_limit_seconds
    }
  end

  def publish_activity(activity_id)
    post "/api/v1/activities/#{activity_id}/publications",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created
    response.parsed_body.fetch("data")
  end

  def start_play_session(share_code:, name: "Jordan", key: SecureRandom.uuid)
    post "/api/v1/play/#{share_code}/sessions",
      params: { play_session: { learner_name: name } },
      headers: { "Idempotency-Key" => key, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
  end

  def answer_question(share_code:, session_id:, question_id:, option_id:, key: SecureRandom.uuid)
    post "/api/v1/play/#{share_code}/sessions/#{session_id}/answers",
      params: { answer: { question_id: question_id, option_id: option_id } },
      headers: { "Idempotency-Key" => key, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
  end

  def fetch_csrf_token
    get "/api/v1/auth/csrf", as: :json
    response.parsed_body.dig("data", "token")
  end

  test "creates, publishes, safely plays, and scores a server-timed quest" do
    activity_id = create_activity(
      questions: [
        question_definition(time_limit_seconds: 15),
        question_definition(prompt: "Which planet is closest to the Sun?", correct_index: 1, time_limit_seconds: 0)
      ]
    )
    publication = publish_activity(activity_id)

    assert_match(/\A[A-HJ-NP-Z2-9]{12}\z/, publication.fetch("share_code"))
    assert_equal 1, publication.fetch("version")
    get "/api/v1/play/#{publication.fetch("share_code")}"

    assert_response :success
    public_activity = response.parsed_body.fetch("data")
    assert_equal "The Solar System Sprint", public_activity.fetch("title")
    assert_equal 2, public_activity.fetch("questions").length
    assert_equal [ 15, 0 ], public_activity.fetch("questions").map { |question| question.fetch("time_limit_seconds") }
    assert_nil public_activity["cover_image_url"]
    refute_includes response.body, "correct_option_id"

    start_play_session(share_code: publication.fetch("share_code"))
    assert_response :created
    session = response.parsed_body.fetch("data")
    assert_equal 0, session.fetch("question_index")
    assert_equal 15, session.fetch("time_limit_seconds")
    questions = public_activity.fetch("questions")
    first_answer = questions[0].fetch("options")[0].fetch("id")
    second_answer = questions[1].fetch("options")[1].fetch("id")

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: questions[0].fetch("id"),
      option_id: first_answer
    )
    assert_response :success
    assert_equal true, response.parsed_body.dig("data", "is_correct")
    assert_equal 1, response.parsed_body.dig("data", "question_index")
    assert_equal 0, response.parsed_body.dig("data", "time_limit_seconds")

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: questions[1].fetch("id"),
      option_id: second_answer
    )
    assert_response :success
    result = response.parsed_body.fetch("data").fetch("attempt")
    assert_equal 200, result.fetch("score")
    assert_equal 200, result.fetch("max_score")
    assert_equal false, result.fetch("results").first.fetch("timed_out")
    assert_equal 1, Attempt.count
  end

  test "starts a play session idempotently without creating duplicates" do
    activity_id = create_activity
    publication = publish_activity(activity_id)
    key = SecureRandom.uuid

    start_play_session(share_code: publication.fetch("share_code"), key: key)
    assert_response :created
    session_id = response.parsed_body.dig("data", "id")

    start_play_session(share_code: publication.fetch("share_code"), key: key)
    assert_response :success
    assert_equal session_id, response.parsed_body.dig("data", "id")
    assert_equal 1, PlaySession.count
  end

  test "answer requests are idempotent and cannot change a submitted answer" do
    activity_id = create_activity
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))
    key = SecureRandom.uuid
    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_id: question.fetch("options")[0].fetch("id"),
      key: key
    )
    assert_response :success
    attempt_id = response.parsed_body.dig("data", "attempt", "id")

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_id: question.fetch("options")[0].fetch("id"),
      key: key
    )
    assert_response :success
    assert_equal attempt_id, response.parsed_body.dig("data", "attempt", "id")

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_id: question.fetch("options")[1].fetch("id"),
      key: key
    )
    assert_response :conflict
    assert_equal "idempotency_conflict", response.parsed_body.dig("error", "code")
    assert_equal 1, Attempt.count
  end

  test "expired questions record no answer and score zero" do
    activity_id = create_activity(
      questions: [
        question_definition(time_limit_seconds: 5),
        question_definition(prompt: "Which planet is closest to the Sun?", correct_index: 1, time_limit_seconds: 0)
      ]
    )
    publication = publish_activity(activity_id)
    questions = publication_questions(publication)
    session = start_session(publication.fetch("share_code"))

    travel 6.seconds do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: questions[0].fetch("id"),
        option_id: questions[0].fetch("options")[0].fetch("id")
      )
    end

    assert_response :success
    assert_equal true, response.parsed_body.dig("data", "timed_out")
    assert_equal false, response.parsed_body.dig("data", "is_correct")

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: questions[1].fetch("id"),
      option_id: questions[1].fetch("options")[1].fetch("id")
    )
    assert_response :success
    result = response.parsed_body.fetch("data").fetch("attempt")
    assert_equal 100, result.fetch("score")
    assert_equal true, result.fetch("results").first.fetch("timed_out")
    assert_nil result.fetch("results").first.fetch("selected_option_id")
  end

  test "a learner cannot skip a timed question before its deadline" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 30) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_id: nil
    )

    assert_response :conflict
    assert_equal "question_not_expired", response.parsed_body.dig("error", "code")
    assert_equal 0, Attempt.count
  end

  test "untimed questions remain available beyond five minutes" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 0) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))

    travel 301.seconds do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
    end

    assert_response :success
    assert_equal 100, response.parsed_body.dig("data", "attempt", "score")
  end

  test "rejects answers for a question other than the current one" do
    activity_id = create_activity(
      questions: [
        question_definition,
        question_definition(prompt: "Which planet is closest to the Sun?", correct_index: 1)
      ]
    )
    publication = publish_activity(activity_id)
    questions = publication_questions(publication)
    session = start_session(publication.fetch("share_code"))

    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: questions[1].fetch("id"),
      option_id: questions[1].fetch("options")[1].fetch("id")
    )

    assert_response :unprocessable_entity
    assert_equal "invalid_answer", response.parsed_body.dig("error", "code")
    assert_equal 0, Attempt.count
  end

  test "rejects invalid question time limits" do
    definition = question_definition(time_limit_seconds: 301)
    post "/api/v1/activities",
      params: { activity: { title: "Invalid timer", questions: [ definition ] } },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_equal 0, Activity.count
  end

  test "questions default to thirty seconds when no time limit is provided" do
    definition = question_definition.except(:time_limit_seconds)
    activity_id = create_activity(questions: [ definition ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)

    assert_equal 30, question.fetch("time_limit_seconds")
  end

  test "does not publish a question with an unknown correct option" do
    definition = question_definition.merge(correct_option_id: "10101010-1010-4101-8101-101010109999")

    post "/api/v1/activities",
      params: { activity: { title: "Invalid activity", questions: [ definition ] } },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_equal 0, Activity.count
  end

  test "published content and question definitions cannot be edited" do
    activity_id = create_activity
    publish_activity(activity_id)
    activity = Activity.find(activity_id)
    question = activity.questions.first

    refute activity.update(title: "Changed after publication")
    refute question.update(prompt: "Changed after publication")
    assert_equal "The Solar System Sprint", activity.reload.title
    assert_equal "Which planet is known as the Red Planet?", question.reload.prompt
  end

  test "unknown game codes do not expose draft activities" do
    create_activity
    get "/api/v1/play/AAAAAAAAAAAA"

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  test "an authenticated educator cannot publish another user's activity" do
    other_user = User.create!(
      google_uid: "another-google-user",
      email: "another@example.test",
      name: "Another educator"
    )
    activity = other_user.activities.create!(
      title: "Private activity",
      description: ""
    )

    post "/api/v1/activities/#{activity.id}/publications",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :not_found
    assert_equal "not_found", response.parsed_body.dig("error", "code")
  end

  private

  def start_session(share_code)
    start_play_session(share_code: share_code)
    assert_response :created
    response.parsed_body.fetch("data")
  end

  def publication_questions(publication)
    get "/api/v1/play/#{publication.fetch("share_code")}"
    assert_response :success
    response.parsed_body.dig("data", "questions")
  end

  def publication_question(publication)
    publication_questions(publication).first
  end
end
