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

  def create_game_room(activity_id)
    post "/api/v1/activities/#{activity_id}/game_rooms",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created
    response.parsed_body.dig("data", "room_code")
  end

  def join_game_room(room_code:, name:)
    post "/api/v1/game_rooms/#{room_code}/participants",
      params: { participant: { learner_name: name } },
      headers: { "Idempotency-Key" => SecureRandom.uuid, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created
    response.parsed_body.dig("data", "session_id")
  end

  def start_game_room(room_code:)
    post "/api/v1/game_rooms/#{room_code}/start",
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :success
    response.parsed_body.fetch("data")
  end

  def answer_game_room(room_code:, session_id:, question_id:, option_id:)
    post "/api/v1/game_rooms/#{room_code}/participants/#{session_id}/answers",
      params: { answer: { question_id: question_id, option_id: option_id } },
      headers: { "Idempotency-Key" => SecureRandom.uuid, "X-CSRF-Token" => fetch_csrf_token },
      as: :json
  end

  def fetch_csrf_token
    get "/api/v1/auth/csrf", as: :json
    response.parsed_body.dig("data", "token")
  end

  test "participant-paced play ignores live timers and records elapsed duration" do
    activity_id = create_activity(
      questions: [
        question_definition(time_limit_seconds: 15),
        question_definition(prompt: "Which planet is closest to the Sun?", correct_index: 1, time_limit_seconds: 30)
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
    assert_equal [ 0, 0 ], public_activity.fetch("questions").map { |question| question.fetch("time_limit_seconds") }
    assert_equal [ false, false ], public_activity.fetch("questions").map { |question| question.fetch("speed_scoring") }
    assert_nil public_activity["cover_image_url"]
    refute_includes response.body, "correct_option_id"

    start_play_session(share_code: publication.fetch("share_code"))
    assert_response :created
    session = response.parsed_body.fetch("data")
    assert_equal 0, session.fetch("question_index")
    assert_equal 0, session.fetch("time_limit_seconds")
    assert_equal 0, session.fetch("time_remaining_seconds")
    questions = public_activity.fetch("questions")
    first_answer = questions[0].fetch("options")[0].fetch("id")
    second_answer = questions[1].fetch("options")[1].fetch("id")

    session_started_at = PlaySession.find(session.fetch("id")).created_at
    travel_to(session_started_at + 16.seconds, with_usec: true) do
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
      assert_equal 0, result.fetch("results").first.fetch("speed_bonus")
      assert_equal 16, result.fetch("duration_seconds")
      assert_equal session_started_at.iso8601(6), result.fetch("started_at")
      assert_equal result.fetch("completed_at"), Attempt.find(result.fetch("id")).submitted_at.iso8601(6)
    end

    assert_equal 1, Attempt.count
  end

  test "defaults omitted question points to one" do
    question = question_definition.except(:points)
    activity_id = create_activity(questions: [ question ])
    publication = publish_activity(activity_id)

    get "/api/v1/play/#{publication.fetch("share_code")}"

    assert_response :success
    assert_equal 1, response.parsed_body.dig("data", "questions", 0, "points")
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

  test "revises a published quest without changing its previous version or learner link" do
    activity_id = create_activity(
      questions: [
        question_definition(prompt: "Alpha", time_limit_seconds: 15),
        question_definition(prompt: "Bravo", time_limit_seconds: 30)
      ]
    )
    original_publication = publish_activity(activity_id)
    original_code = original_publication.fetch("share_code")
    original_version = ActivityVersion.find_by!(share_code: original_code)
    assert_equal [ "Alpha", "Bravo" ],
      original_version.question_snapshot.map { |question| question.fetch("prompt") }
    assert_equal 100, original_version.question_snapshot.first.fetch("speed_bonus_points")
    get "/api/v1/activities/#{activity_id}", headers: { "Accept" => "application/json" }
    assert_response :success
    original_questions = response.parsed_body.dig("data", "questions")
    revision_questions = [
      original_questions.fetch(1),
      original_questions.fetch(0).merge(
        prompt: "Alpha, revised",
        correct_option_id: original_questions.fetch(0).fetch("options").fetch(1).fetch("id"),
        correct_option_ids: [ original_questions.fetch(0).fetch("options").fetch(1).fetch("id") ],
        speed_bonus_points: 500,
        time_limit_seconds: 45
      )
    ]

    post "/api/v1/activities/#{activity_id}/revisions",
      params: {
        revision: {
          title: "The Solar System, Revisited",
          expected_version: 1,
          shuffle_questions: false,
          speed_scoring: false,
          questions: revision_questions
        }
      },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :created
    revised_publication = response.parsed_body.fetch("data")
    assert_equal activity_id, revised_publication.fetch("activity_id")
    assert_equal "The Solar System, Revisited", revised_publication.fetch("title")
    assert_equal 2, revised_publication.fetch("version")
    refute_equal original_code, revised_publication.fetch("share_code")

    get "/api/v1/play/#{original_code}"
    assert_response :success
    assert_equal [ "Alpha", "Bravo" ],
      response.parsed_body.dig("data", "questions").map { |question| question.fetch("prompt") }
    assert_equal "The Solar System Sprint", response.parsed_body.dig("data", "title")

    get "/api/v1/play/#{revised_publication.fetch("share_code")}"
    assert_response :success
    revised_questions = response.parsed_body.dig("data", "questions")
    assert_equal "The Solar System, Revisited", response.parsed_body.dig("data", "title")
    assert_equal [ "Bravo", "Alpha, revised" ], revised_questions.map { |question| question.fetch("prompt") }
    assert_equal 500, revised_questions.last.fetch("speed_bonus_points")
    assert_equal [ 0, 0 ], revised_questions.map { |question| question.fetch("time_limit_seconds") }

    get "/api/v1/activities/#{activity_id}", headers: { "Accept" => "application/json" }
    assert_response :success
    creator_activity = response.parsed_body.fetch("data")
    assert_equal "The Solar System, Revisited", creator_activity.fetch("title")
    assert_equal 2, creator_activity.fetch("version")
    assert_equal revised_publication.fetch("share_code"), creator_activity.fetch("share_code")
    assert_equal false, ActivityVersion.find_by!(share_code: revised_publication.fetch("share_code")).shuffle_questions
    assert_equal false, ActivityVersion.find_by!(share_code: revised_publication.fetch("share_code")).speed_scoring
    assert_equal false, creator_activity.fetch("speed_scoring")
    assert_equal [ 30, 45 ], creator_activity.fetch("questions").map { |question| question.fetch("time_limit_seconds") }
    assert_equal [ "Bravo", "Alpha, revised" ],
      creator_activity.fetch("questions").map { |question| question.fetch("prompt") }
    assert_equal revision_questions.last.fetch("correct_option_id"),
      creator_activity.fetch("questions").last.fetch("correct_option_id") do
        "Creator details should return the revised correct answer."
      end
    refute_equal original_questions.first.fetch("correct_option_id"),
      creator_activity.fetch("questions").last.fetch("correct_option_id")
    assert_equal [ "Alpha", "Bravo" ],
      Activity.find(activity_id).questions.map(&:prompt)
  end

  test "rejects stale quest revisions and revisions from another creator" do
    activity_id = create_activity
    publish_activity(activity_id)
    get "/api/v1/activities/#{activity_id}", headers: { "Accept" => "application/json" }
    question = response.parsed_body.dig("data", "questions", 0)
    revision = {
      expected_version: 1,
      shuffle_questions: false,
      speed_scoring: true,
      questions: [ question ]
    }
    post "/api/v1/activities/#{activity_id}/revisions",
      params: { revision: },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :created

    post "/api/v1/activities/#{activity_id}/revisions",
      params: { revision: },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :conflict
    assert_equal "stale_activity_revision", response.parsed_body.dig("error", "code")

    invalid_revision = revision.merge(
      expected_version: 2,
      questions: [ question.merge(time_limit_seconds: 301) ]
    )
    post "/api/v1/activities/#{activity_id}/revisions",
      params: { revision: invalid_revision },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :unprocessable_entity
    assert_equal 2, ActivityVersion.where(activity_id: activity_id).count

    stranger = User.create!(
      email: "revision-owner@example.test",
      name: "Another Educator",
      google_uid: "revision-owner-google-user"
    )
    stranger_activity = stranger.activities.create!(title: "Private quest")
    post "/api/v1/activities/#{stranger_activity.id}/revisions",
      params: { revision: },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json
    assert_response :not_found
  end

  test "publishes and scores a multiple-select question without exposing its answer key to learners" do
    definition = question_definition(time_limit_seconds: 30)
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
    definition = question_definition(time_limit_seconds: 30)
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

  test "participant-paced scores use base points regardless of configured live timers" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 10) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))
    started_at = PlaySession.find(session.fetch("id")).created_at

    travel_to(started_at + 15.seconds, with_usec: true) do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
    end

    assert_response :success
    result = response.parsed_body.dig("data", "attempt")
    assert_equal 100, result.fetch("max_score")
    assert_equal 100, result.fetch("score")
    assert_equal 0, result.fetch("results").first.fetch("speed_bonus")
    assert_equal false, result.fetch("results").first.fetch("timed_out")
    assert_equal 15, result.fetch("duration_seconds")
  end

  test "live speed scoring honors its bonus cap and gives equal-time answers equal points" do
    definition = question_definition(time_limit_seconds: 10).merge(
      points: 1,
      speed_bonus_points: 500
    )
    activity_id = create_activity(questions: [ definition ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    room_code = create_game_room(activity_id)
    sessions = 2.times.map { |index| join_game_room(room_code:, name: "Learner #{index + 1}") }
    start_time = Time.current
    travel_to(start_time, with_usec: true) { start_game_room(room_code:) }

    travel_to(start_time + 5.seconds, with_usec: true) do
      answers = sessions.map do |session_id|
        answer_game_room(
          room_code:,
          session_id:,
          question_id: question.fetch("id"),
          option_id: question.fetch("options")[0].fetch("id")
        )
        assert_response :success
        response.parsed_body.fetch("data")
      end
      assert_equal [ 251, 251 ], answers.map { |answer| answer.fetch("points_awarded") }
      assert_equal [ 250, 250 ], answers.map { |answer| answer.fetch("speed_bonus") }

      post "/api/v1/game_rooms/#{room_code}/advance",
        headers: { "X-CSRF-Token" => fetch_csrf_token },
        as: :json
      assert_response :success
      room_result = response.parsed_body.fetch("data")
      assert_equal 5, room_result.fetch("duration_seconds")

      attempts = Attempt.where(game_room_id: GameRoom.find_by!(room_code: room_code).id).order(:learner_name)
      assert_equal [ 251, 251 ], attempts.map(&:score)
      assert_equal [ 501, 501 ], attempts.map(&:max_score)
      assert_equal [ start_time, start_time ], attempts.map(&:started_at)
      assert_equal [ 5_000, 5_000 ], attempts.map(&:total_response_time_ms)
    end
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
    assert_equal true, response.parsed_body.dig("data", "participants").any? { |participant| participant.fetch("answered") }

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

  test "host navigation preserves answer locks and previously started question timers" do
    activity_id = create_activity(
      questions: [
        question_definition(prompt: "Alpha"),
        question_definition(prompt: "Bravo"),
        question_definition(prompt: "Charlie")
      ],
      speed_scoring: false
    )
    publication = publish_activity(activity_id)
    questions = publication_questions(publication)
    room_code = create_game_room(activity_id)
    session_id = join_game_room(room_code:, name: "Jordan")
    join_game_room(room_code:, name: "Jordan")
    start_time = Time.current

    started_room = travel_to(start_time, with_usec: true) { start_game_room(room_code:) }
    participant_keys = started_room.fetch("standings").map { |entry| entry.fetch("participant_key") }
    assert_equal 2, participant_keys.uniq.length
    public_standings = Activities::Serializers::GameRoomSerializer
      .call(GameRoom.find_by!(room_code:))
      .fetch(:standings)
    refute public_standings.first.key?(:participant_key)
    travel_to(start_time + 4.seconds, with_usec: true) do
      answer_game_room(
        room_code:,
        session_id:,
        question_id: questions[0].fetch("id"),
        option_id: questions[0].fetch("options")[0].fetch("id")
      )
      assert_response :success
    end

    travel_to(start_time + 8.seconds, with_usec: true) do
      post "/api/v1/game_rooms/#{room_code}/advance",
        params: { question_index: 2 },
        headers: { "X-CSRF-Token" => fetch_csrf_token },
        as: :json
      assert_response :success
      assert_equal 2, response.parsed_body.dig("data", "question_index")
      assert_equal 30, response.parsed_body.dig("data", "time_remaining_seconds").round
    end

    travel_to(start_time + 12.seconds, with_usec: true) do
      post "/api/v1/game_rooms/#{room_code}/advance",
        params: { question_index: 0 },
        headers: { "X-CSRF-Token" => fetch_csrf_token },
        as: :json
      assert_response :success
      assert_equal 0, response.parsed_body.dig("data", "question_index")
      assert_equal 18, response.parsed_body.dig("data", "time_remaining_seconds").round
      assert_equal true,
        response.parsed_body.dig("data", "participants").any? { |participant| participant.fetch("answered") }

      answer_game_room(
        room_code:,
        session_id:,
        question_id: questions[0].fetch("id"),
        option_id: questions[0].fetch("options")[1].fetch("id")
      )
      assert_response :unprocessable_entity
      assert_equal "invalid_answer", response.parsed_body.dig("error", "code")
    end

    travel_to(start_time + 15.seconds, with_usec: true) do
      post "/api/v1/game_rooms/#{room_code}/advance",
        params: { question_index: 2 },
        headers: { "X-CSRF-Token" => fetch_csrf_token },
        as: :json
      assert_response :success
      assert_equal 23, response.parsed_body.dig("data", "time_remaining_seconds").round

      post "/api/v1/game_rooms/#{room_code}/advance",
        headers: { "X-CSRF-Token" => fetch_csrf_token },
        as: :json
      assert_response :success
      assert_equal "completed", response.parsed_body.dig("data", "status")
      game_room_id = GameRoom.find_by!(room_code:).id
      attempt = Attempt.find_by!(game_room_id:)
      assert_equal [ 0, 100 ], Attempt.where(game_room_id:).pluck(:score).sort
      assert_equal 3, attempt.responses.length
      scores_by_question = attempt.responses.to_h do |result|
        [ result.fetch("question_id"), result.fetch("points_awarded") ]
      end
      assert_equal(
        {
          questions[0].fetch("id") => 100,
          questions[1].fetch("id") => 0,
          questions[2].fetch("id") => 0
        },
        scores_by_question
      )
    end
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

  test "participant-paced questions remain answerable after the configured live timer" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 5) ])
    publication = publish_activity(activity_id)
    question = publication_question(publication)
    session = start_session(publication.fetch("share_code"))
    started_at = PlaySession.find(session.fetch("id")).created_at

    travel_to(started_at + 6.seconds, with_usec: true) do
      answer_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_id: question.fetch("options")[0].fetch("id")
      )
      assert_response :success
      result = response.parsed_body.fetch("data").fetch("attempt")
      assert_equal false, result.fetch("results").first.fetch("timed_out")
      assert_equal 100, result.fetch("score")
      assert_equal 100, result.fetch("max_score")
      assert_equal 6, result.fetch("duration_seconds")
    end
  end

  test "participant-paced multiple-select questions have no per-question deadline" do
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

    started_at = PlaySession.find(session.fetch("id")).created_at
    travel_to(started_at + 6.seconds) do
      answer_multiple_question(
        share_code: publication.fetch("share_code"),
        session_id: session.fetch("id"),
        question_id: question.fetch("id"),
        option_ids: correct_option_ids
      )
      assert_response :success
      data = response.parsed_body.fetch("data")
      result = data.fetch("attempt").fetch("results").first
      assert_equal false, data.fetch("timed_out")
      assert_equal correct_option_ids.sort, result.fetch("selected_option_ids").sort
      assert_equal true, result.fetch("correct")
      assert_equal 100, data.dig("attempt", "score")
      assert_equal 0, result.fetch("speed_bonus")
    end
  end

  test "a learner cannot skip a participant-paced question without answering" do
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

  test "participant-paced questions remain available beyond five minutes" do
    activity_id = create_activity(questions: [ question_definition(time_limit_seconds: 5) ])
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

  test "rejects a zero question timer because timing is selected by play mode" do
    definition = question_definition(time_limit_seconds: 0)
    post "/api/v1/activities",
      params: { activity: { title: "Untimed timer", questions: [ definition ] } },
      headers: { "X-CSRF-Token" => fetch_csrf_token },
      as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body.dig("error", "code")
    assert_equal 0, Activity.count
  end

  test "questions default to thirty seconds when no time limit is provided" do
    definition = question_definition.except(:time_limit_seconds)
    activity_id = create_activity(questions: [ definition ])
    publish_activity(activity_id)

    get "/api/v1/activities/#{activity_id}", headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 30, response.parsed_body.dig("data", "questions", 0, "time_limit_seconds")
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
