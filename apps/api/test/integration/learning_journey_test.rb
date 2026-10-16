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

  def create_activity(questions: [ question_definition ], shuffle_questions: false, speed_scoring: true)
    post "/api/v1/activities",
      params: {
        activity: {
          title: "The Solar System Sprint",
          description: "A quick trip through our cosmic neighborhood.",
          shuffle_questions: shuffle_questions,
          speed_scoring: speed_scoring,
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

  def answer_multiple_question(share_code:, session_id:, question_id:, option_ids:, key: SecureRandom.uuid)
    post "/api/v1/play/#{share_code}/sessions/#{session_id}/answers",
      params: { answer: { question_id: question_id, option_ids: option_ids } },
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

    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, publication.fetch("share_code"))
    assert_equal activity_id, publication.fetch("activity_id")
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
    assert_equal 300, result.fetch("score")
    assert_equal 300, result.fetch("max_score")
    assert_equal false, result.fetch("results").first.fetch("timed_out")
    assert_equal 1, Attempt.count
  end

  test "lists only the signed-in creator's quests with publication and play summaries" do
    activity_id = create_activity
    publication = publish_activity(activity_id)
    stranger = User.create!(
      email: "another-educator@example.test",
      name: "Another Educator",
      google_uid: "another-google-user"
    )
    stranger.activities.create!(title: "Private quest")

    get "/api/v1/activities", headers: { "Accept" => "application/json" }

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal({ "total" => 1, "published" => 1, "plays" => 0 }, data.fetch("summary"))
    assert_equal 1, data.fetch("activities").length
    activity = data.fetch("activities").first
    assert_equal activity_id, activity.fetch("id")
    assert_equal publication.fetch("share_code"), activity.fetch("share_code")
    assert_equal 1, activity.fetch("version")
    assert_equal 1, activity.fetch("question_count")
    refute_equal stranger.activities.first.id, activity.fetch("id")

    get "/api/v1/activities/#{stranger.activities.first.id}", headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "publishes and scores a multiple-select question without exposing its answer key to learners" do
    definition = question_definition(time_limit_seconds: 0)
    correct_option_ids = [ definition.fetch(:options)[0].fetch(:id), definition.fetch(:options)[2].fetch(:id) ]
    activity_id = create_activity(
      questions: [
        definition.merge(
          question_type: "multiple_select",
          correct_option_ids: correct_option_ids
        )
      ]
    )
    publication = publish_activity(activity_id)
    get "/api/v1/activities/#{activity_id}", headers: { "Accept" => "application/json" }

    assert_response :success
    creator_question = response.parsed_body.dig("data", "questions", 0)
    assert_equal "multiple_select", creator_question.fetch("question_type")
    assert_equal correct_option_ids, creator_question.fetch("correct_option_ids")

    get "/api/v1/play/#{publication.fetch("share_code")}"
    assert_response :success
    public_question = response.parsed_body.dig("data", "questions", 0)
    assert_equal "multiple_select", public_question.fetch("question_type")
    refute_includes response.body, "correct_option_ids"

    start_play_session(share_code: publication.fetch("share_code"))
    session = response.parsed_body.dig("data", "id")
    question_id = public_question.fetch("id")
    answer_multiple_question(
      share_code: publication.fetch("share_code"),
      session_id: session,
      question_id: question_id,
      option_ids: correct_option_ids
    )

    assert_response :success
    result = response.parsed_body.dig("data", "attempt", "results", 0)
    assert_equal true, result.fetch("correct")
    assert_equal correct_option_ids.sort, result.fetch("selected_option_ids").sort
    assert_equal correct_option_ids.sort, result.fetch("correct_option_ids").sort
    assert_equal 100, response.parsed_body.dig("data", "attempt", "score")
  end

  test "rejects duplicate and unavailable multiple-select answers" do
    definition = question_definition(time_limit_seconds: 0)
    correct_option_ids = [ definition.fetch(:options)[0].fetch(:id), definition.fetch(:options)[2].fetch(:id) ]
    activity_id = create_activity(
      questions: [
        definition.merge(
          question_type: "multiple_select",
          correct_option_ids: correct_option_ids
        )
      ]
    )
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))

    answer_multiple_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_ids: [ correct_option_ids.first, correct_option_ids.first ]
    )
    assert_response :unprocessable_entity

    answer_multiple_question(
      share_code: publication.fetch("share_code"),
      session_id: session.fetch("id"),
      question_id: question.fetch("id"),
      option_ids: [ "10101010-1010-4101-8101-101010101099" ]
    )
    assert_response :unprocessable_entity
    assert_equal 0, Attempt.count
  end

  test "speed scoring awards a server-measured proportional bonus and caps the maximum" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 10) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))

    travel 5.seconds do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
    end

    assert_response :success
    result = response.parsed_body.dig("data", "attempt")
    assert_equal 200, result.fetch("max_score")
    response_time_ms = result.fetch("results").first.fetch("response_time_ms")
    expected_bonus = (100 * [ 1 - response_time_ms / 10_000.0, 0 ].max).round
    assert_equal 100 + expected_bonus, result.fetch("score")
    assert_equal expected_bonus, result.fetch("results").first.fetch("speed_bonus")
    assert_operator response_time_ms, :>=, 0
  end

  test "speed scoring can be disabled and published questions can be shuffled" do
    activity_id = create_activity(
      questions: [
        question_definition(prompt: "Alpha", time_limit_seconds: 10),
        question_definition(prompt: "Bravo", time_limit_seconds: 10),
        question_definition(prompt: "Charlie", time_limit_seconds: 10)
      ],
      shuffle_questions: true,
      speed_scoring: false
    )
    publication = publish_activity(activity_id)
    version = ActivityVersion.find_by!(share_code: publication.fetch("share_code"))

    assert_equal false, version.question_snapshot.first.fetch("speed_scoring")
    assert_equal 3, version.question_snapshot.length
    version.question_snapshot.each do |question|
      assert_includes question.fetch("options").map { |option| option.fetch("id") }, question.fetch("correct_option_id")
    end

    session = start_session(publication.fetch("share_code"))
    publication_questions(publication).each do |question|
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
      assert_response :success
    end

    result = response.parsed_body.dig("data", "attempt")
    assert_equal 300, result.fetch("score")
    assert_equal 300, result.fetch("max_score")
    assert_equal [ 0, 0, 0 ], result.fetch("results").map { |item| item.fetch("speed_bonus") }
  end

  test "host-paced rooms synchronize participants and publish a finalized podium" do
    definition = question_definition(time_limit_seconds: 10)
    definition = definition.merge(
      question_type: "multiple_select",
      correct_option_ids: [ definition.fetch(:options)[0].fetch(:id), definition.fetch(:options)[2].fetch(:id) ]
    )
    activity_id = create_activity(questions: [ definition ])
    publication = publish_activity(activity_id)
    post "/api/v1/activities/#{activity_id}/game_rooms",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created
    room_code = response.parsed_body.dig("data", "room_code")
    assert_match(/\A[A-HJ-NP-Z2-9]{6}\z/, room_code)
    get "/api/v1/join/#{room_code}"
    assert_response :success
    assert_equal "live_room", response.parsed_body.dig("data", "kind")
    assert_equal "/room/#{room_code}", response.parsed_body.dig("data", "path")

    post "/api/v1/game_rooms/#{room_code}/participants",
      params: { participant: { learner_name: "Jordan" } },
      headers: { "Idempotency-Key" => SecureRandom.uuid, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created
    session_id = response.parsed_body.dig("data", "session_id")

    get "/api/v1/game_rooms/#{room_code}"
    assert_response :success
    participant = response.parsed_body.dig("data", "participants").first
    assert_equal "Jordan", participant.fetch("learner_name")
    assert_equal false, participant.fetch("answered")

    patch "/api/v1/game_rooms/#{room_code}/participants/#{session_id}",
      params: { participant: { learner_name: "Jordan Updated" } },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :success
    assert_equal "Jordan Updated", response.parsed_body.dig("data", "learner_name")

    post "/api/v1/game_rooms/#{room_code}/start",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :success
    assert_equal "active", response.parsed_body.dig("data", "status")

    question = publication_question(publication)
    post "/api/v1/game_rooms/#{room_code}/participants/#{session_id}/answers",
      params: {
        answer: {
          question_id: question.fetch("id"),
          option_ids: definition.fetch(:correct_option_ids)
        }
      },
      headers: { "Idempotency-Key" => SecureRandom.uuid, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :success
    assert_operator response.parsed_body.dig("data", "points_awarded"), :>, 100
    get "/api/v1/game_rooms/#{room_code}"
    assert_response :success
    assert_equal true, response.parsed_body.dig("data", "participants", 0, "answered")

    post "/api/v1/game_rooms/#{room_code}/advance",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :success
    assert_equal "completed", response.parsed_body.dig("data", "status")
    assert_equal true, response.parsed_body.dig("data", "standings_final")
    assert_equal "Jordan Updated", response.parsed_body.dig("data", "podium", 0, "learner_name")
    attempt = Attempt.find_by!(game_room_id: GameRoom.find_by!(room_code: room_code).id)
    assert_equal 1, Attempt.where(game_room_id: attempt.game_room_id).count
    assert_equal definition.fetch(:correct_option_ids).sort, attempt.responses.first.fetch("option_ids").sort
    assert_operator attempt.score, :>, 100
  end

  test "join links resolve both live rooms and self-paced activities" do
    activity_id = create_activity
    publication = publish_activity(activity_id)

    get "/api/v1/join/#{publication.fetch("share_code")}"
    assert_response :success
    assert_equal "self_paced", response.parsed_body.dig("data", "kind")
    assert_equal "/play/#{publication.fetch("share_code")}", response.parsed_body.dig("data", "path")

    get "/api/v1/join/ABCD23456789"
    assert_response :not_found
  end

  test "participant-paced leaderboard stays provisional and ranks server-scored attempts" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 10) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)

    fast_session = start_play_session(share_code: publication.fetch("share_code"), name: "Fast Learner")
    assert_response :created
    fast_session = response.parsed_body.fetch("data")
    answer_question(
      share_code: publication.fetch("share_code"),
      session_id: fast_session.fetch("id"),
      question_id: question.fetch("id"),
      option_id: question.fetch("options")[0].fetch("id")
    )
    assert_response :success

    slower_session = start_play_session(share_code: publication.fetch("share_code"), name: "Second Learner")
    assert_response :created
    slower_session = response.parsed_body.fetch("data")
    travel 5.seconds do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: slower_session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
    end
    assert_response :success

    get "/api/v1/play/#{publication.fetch("share_code")}/leaderboard"

    assert_response :success
    leaderboard = response.parsed_body.fetch("data")
    assert_equal "provisional", leaderboard.fetch("status")
    assert_equal 2, leaderboard.fetch("participant_count")
    assert_equal "Fast Learner", leaderboard.fetch("podium").first.fetch("learner_name")
    assert_equal [ 1, 2 ], leaderboard.fetch("standings").map { |entry| entry.fetch("rank") }
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

  test "expired multiple-select questions record an empty answer set and score zero" do
    definition = question_definition(time_limit_seconds: 5)
    correct_option_ids = [ definition.fetch(:options)[0].fetch(:id), definition.fetch(:options)[2].fetch(:id) ]
    activity_id = create_activity(
      questions: [
        definition.merge(
          question_type: "multiple_select",
          correct_option_ids: correct_option_ids
        )
      ]
    )
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))

    travel 6.seconds do
      answer_multiple_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_ids: []
      )
    end

    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal true, data.fetch("timed_out")
    result = data.fetch("attempt").fetch("results").first
    assert_equal [], result.fetch("selected_option_ids")
    assert_equal false, result.fetch("correct")
    assert_equal 0, data.dig("attempt", "score")
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
