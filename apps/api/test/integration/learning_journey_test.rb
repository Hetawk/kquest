require "test_helper"

class LearningJourneyTest < ActionDispatch::IntegrationTest
  def create_activity(questions: [ question_definition ])
    post "/api/v1/activities",
         params: {
           activity: {
             title: "The Solar System Sprint",
             description: "A quick trip through our cosmic neighborhood.",
             questions: questions
           }
         },
         as: :json

    assert_response :created
    response.parsed_body.fetch("data").fetch("id")
  end

  def question_definition(prompt: "Which planet is known as the Red Planet?", correct_index: 0)
    options = [
      { id: "10101010-1010-4101-8101-101010101001", text: "Mars" },
      { id: "10101010-1010-4101-8101-101010101002", text: "Venus" },
      { id: "10101010-1010-4101-8101-101010101003", text: "Jupiter" }
    ]

    {
      prompt: prompt,
      options: options,
      correct_option_id: options.fetch(correct_index).fetch(:id),
      points: 100
    }
  end

  def publish_activity(activity_id)
    post "/api/v1/activities/#{activity_id}/publications", as: :json
    assert_response :created
    response.parsed_body.fetch("data")
  end

  def submit_attempt(share_code:, submission_key:, responses:, name: "Jordan")
    post "/api/v1/play/#{share_code}/attempts",
         params: { attempt: { learner_name: name, responses: responses } },
         headers: { "Idempotency-Key" => submission_key },
         as: :json
  end

  test "creates, publishes, safely plays, and scores a server-graded quest" do
    activity_id = create_activity(
      questions: [
        question_definition,
        question_definition(prompt: "Which planet is closest to the Sun?", correct_index: 1)
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
    refute_includes response.body, "correct_option_id"

    questions = public_activity.fetch("questions")
    submission_key = "00000000-0000-4000-8000-000000000001"
    responses = [
      { question_id: questions[0].fetch("id"), option_id: questions[0].fetch("options")[0].fetch("id") },
      { question_id: questions[1].fetch("id"), option_id: questions[1].fetch("options")[1].fetch("id") }
    ]

    submit_attempt(
      share_code: publication.fetch("share_code"),
      submission_key: submission_key,
      responses: responses
    )

    assert_response :created
    attempt_id = response.parsed_body.fetch("data").fetch("id")
    assert_equal 200, response.parsed_body.dig("data", "score")
    assert_equal 200, response.parsed_body.dig("data", "max_score")

    submit_attempt(
      share_code: publication.fetch("share_code"),
      submission_key: submission_key,
      responses: responses
    )

    assert_response :success
    assert_equal attempt_id, response.parsed_body.dig("data", "id")
    assert_equal 1, Attempt.count
  end

  test "a reused idempotency key cannot change answers" do
    activity_id = create_activity
    publication = publish_activity(activity_id)
    get "/api/v1/play/#{publication.fetch("share_code")}"
    question = response.parsed_body.dig("data", "questions", 0)
    responses = [
      { question_id: question.fetch("id"), option_id: question.fetch("options")[0].fetch("id") }
    ]
    key = "00000000-0000-4000-8000-000000000002"

    submit_attempt(share_code: publication.fetch("share_code"), submission_key: key, responses: responses)
    assert_response :created
    submit_attempt(
      share_code: publication.fetch("share_code"),
      submission_key: key,
      responses: [ responses.first.merge(option_id: question.fetch("options")[1].fetch("id")) ]
    )

    assert_response :conflict
    assert_equal "idempotency_conflict", response.parsed_body.dig("error", "code")
    assert_equal 1, Attempt.count
  end

  test "rejects invalid and duplicate answers without creating an attempt" do
    activity_id = create_activity
    publication = publish_activity(activity_id)
    get "/api/v1/play/#{publication.fetch("share_code")}"
    question = response.parsed_body.dig("data", "questions", 0)
    answer = { question_id: question.fetch("id"), option_id: question.fetch("options")[0].fetch("id") }

    submit_attempt(
      share_code: publication.fetch("share_code"),
      submission_key: "00000000-0000-4000-8000-000000000003",
      responses: [ answer, answer ]
    )

    assert_response :unprocessable_entity
    assert_equal "invalid_responses", response.parsed_body.dig("error", "code")
    assert_equal 0, Attempt.count
  end

  test "does not publish a question with an unknown correct option" do
    definition = question_definition.merge(correct_option_id: "10101010-1010-4101-8101-101010109999")

    post "/api/v1/activities",
         params: { activity: { title: "Invalid activity", questions: [ definition ] } },
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
end
