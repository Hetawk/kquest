# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_16_000011) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title", limit: 120, null: false
    t.text "description", default: "", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.uuid "uploaded_asset_id"
    t.boolean "shuffle_questions", default: false, null: false
    t.boolean "speed_scoring", default: true, null: false
    t.index ["uploaded_asset_id"], name: "index_activities_on_uploaded_asset_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying]::text[])", name: "activities_status_valid"
  end

  create_table "activity_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_id", null: false
    t.integer "version_number", null: false
    t.string "share_code", limit: 6, null: false
    t.jsonb "question_snapshot", default: [], null: false
    t.datetime "published_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "cover_image_url"
    t.boolean "shuffle_questions", default: false, null: false
    t.boolean "speed_scoring", default: true, null: false
    t.string "title", limit: 120, null: false
    t.index ["activity_id", "version_number"], name: "index_activity_versions_on_activity_id_and_version_number", unique: true
    t.index ["activity_id"], name: "index_activity_versions_on_activity_id"
    t.index ["share_code"], name: "index_activity_versions_on_share_code", unique: true
  end

  create_table "attempts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_version_id", null: false
    t.string "learner_name", limit: 80, null: false
    t.string "submission_key", limit: 36, null: false
    t.jsonb "responses", default: [], null: false
    t.integer "score", null: false
    t.integer "max_score", null: false
    t.datetime "submitted_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "total_response_time_ms", default: 0, null: false
    t.uuid "game_room_id"
    t.datetime "started_at"
    t.index ["activity_version_id", "game_room_id", "score", "total_response_time_ms"], name: "index_attempts_on_leaderboard"
    t.index ["activity_version_id", "submitted_at"], name: "index_attempts_on_activity_version_id_and_submitted_at"
    t.index ["activity_version_id"], name: "index_attempts_on_activity_version_id"
    t.index ["game_room_id"], name: "index_attempts_on_game_room_id"
    t.index ["submission_key"], name: "index_attempts_on_submission_key", unique: true
    t.check_constraint "max_score > 0", name: "attempts_max_score_positive"
    t.check_constraint "score >= 0 AND score <= max_score", name: "attempts_score_valid"
  end

  create_table "auth_challenges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "email", null: false
    t.string "purpose", null: false
    t.string "code_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "last_sent_at", null: false
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email", "purpose", "created_at"], name: "index_auth_challenges_on_email_and_purpose_and_created_at"
    t.index ["expires_at"], name: "index_auth_challenges_on_expires_at"
    t.index ["user_id"], name: "index_auth_challenges_on_user_id"
    t.check_constraint "attempts >= 0 AND attempts <= 5", name: "auth_challenges_attempts_range"
  end

  create_table "game_rooms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_version_id", null: false
    t.uuid "host_user_id", null: false
    t.string "room_code", limit: 6, null: false
    t.string "status", default: "waiting", null: false
    t.integer "current_question_index", default: 0, null: false
    t.datetime "question_started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "started_at"
    t.jsonb "question_start_times", default: {}, null: false
    t.index ["activity_version_id"], name: "index_game_rooms_on_activity_version_id"
    t.index ["host_user_id"], name: "index_game_rooms_on_host_user_id"
    t.index ["room_code"], name: "index_game_rooms_on_room_code", unique: true
    t.check_constraint "current_question_index >= 0", name: "game_rooms_question_index_nonnegative"
    t.check_constraint "status::text = ANY (ARRAY['waiting'::character varying, 'active'::character varying, 'completed'::character varying]::text[])", name: "game_rooms_status_valid"
  end

  create_table "play_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_version_id", null: false
    t.string "learner_name", limit: 80, null: false
    t.string "start_key", limit: 36, null: false
    t.string "submission_key", limit: 36, null: false
    t.integer "current_question_index", default: 0, null: false
    t.jsonb "responses", default: [], null: false
    t.datetime "question_started_at"
    t.datetime "expires_at", null: false
    t.datetime "completed_at"
    t.string "last_request_key", limit: 36
    t.string "last_request_fingerprint", limit: 64
    t.jsonb "last_response"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "game_room_id"
    t.index ["activity_version_id"], name: "index_play_sessions_on_activity_version_id"
    t.index ["expires_at"], name: "index_play_sessions_on_expires_at"
    t.index ["game_room_id", "start_key"], name: "index_play_sessions_on_game_room_id_and_start_key", unique: true
    t.index ["game_room_id"], name: "index_play_sessions_on_game_room_id"
    t.index ["start_key"], name: "index_play_sessions_on_start_key", unique: true
    t.index ["submission_key"], name: "index_play_sessions_on_submission_key", unique: true
    t.check_constraint "current_question_index >= 0", name: "play_sessions_question_index_nonnegative"
  end

  create_table "questions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_id", null: false
    t.integer "position", null: false
    t.string "question_type", default: "single_choice", null: false
    t.text "prompt", null: false
    t.jsonb "options", default: [], null: false
    t.string "correct_option_id", null: false
    t.integer "points", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "time_limit_seconds", default: 30, null: false
    t.jsonb "correct_option_ids", default: [], null: false
    t.integer "speed_bonus_points", default: 100, null: false
    t.index ["activity_id", "position"], name: "index_questions_on_activity_id_and_position", unique: true
    t.index ["activity_id"], name: "index_questions_on_activity_id"
    t.check_constraint "\"position\" > 0", name: "questions_position_positive"
    t.check_constraint "points >= 1 AND points <= 1000", name: "questions_points_valid"
    t.check_constraint "speed_bonus_points >= 0 AND speed_bonus_points <= 100000", name: "questions_speed_bonus_points_valid"
    t.check_constraint "time_limit_seconds = 0 OR time_limit_seconds >= 5 AND time_limit_seconds <= 300", name: "questions_time_limit_valid"
    t.check_constraint "time_limit_seconds >= 5 AND time_limit_seconds <= 300", name: "questions_time_limit_seconds_valid"
  end

  create_table "uploaded_assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "provider_asset_id", null: false
    t.text "public_url", null: false
    t.string "content_type", null: false
    t.integer "file_size", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_asset_id"], name: "index_uploaded_assets_on_provider_asset_id", unique: true
    t.index ["user_id"], name: "index_uploaded_assets_on_user_id"
    t.check_constraint "file_size > 0", name: "uploaded_assets_positive_size"
  end

  create_table "user_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_user_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "google_uid"
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "suspended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "password_digest"
    t.datetime "email_verified_at"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  add_foreign_key "activities", "uploaded_assets"
  add_foreign_key "activities", "users"
  add_foreign_key "activity_versions", "activities"
  add_foreign_key "attempts", "activity_versions"
  add_foreign_key "attempts", "game_rooms"
  add_foreign_key "auth_challenges", "users"
  add_foreign_key "game_rooms", "activity_versions"
  add_foreign_key "game_rooms", "users", column: "host_user_id"
  add_foreign_key "play_sessions", "activity_versions"
  add_foreign_key "play_sessions", "game_rooms"
  add_foreign_key "questions", "activities"
  add_foreign_key "uploaded_assets", "users"
  add_foreign_key "user_sessions", "users"
end
