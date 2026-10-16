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

ActiveRecord::Schema[8.1].define(version: 2026_10_16_000003) do
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
    t.index ["uploaded_asset_id"], name: "index_activities_on_uploaded_asset_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'published'::character varying]::text[])", name: "activities_status_valid"
  end

  create_table "activity_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_id", null: false
    t.integer "version_number", null: false
    t.string "share_code", limit: 12, null: false
    t.jsonb "question_snapshot", default: [], null: false
    t.datetime "published_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "cover_image_url"
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
    t.index ["activity_version_id", "submitted_at"], name: "index_attempts_on_activity_version_id_and_submitted_at"
    t.index ["activity_version_id"], name: "index_attempts_on_activity_version_id"
    t.index ["submission_key"], name: "index_attempts_on_submission_key", unique: true
    t.check_constraint "max_score > 0", name: "attempts_max_score_positive"
    t.check_constraint "score >= 0 AND score <= max_score", name: "attempts_score_valid"
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
    t.index ["activity_version_id"], name: "index_play_sessions_on_activity_version_id"
    t.index ["expires_at"], name: "index_play_sessions_on_expires_at"
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
    t.integer "points", default: 100, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "time_limit_seconds", default: 30, null: false
    t.index ["activity_id", "position"], name: "index_questions_on_activity_id_and_position", unique: true
    t.index ["activity_id"], name: "index_questions_on_activity_id"
    t.check_constraint "\"position\" > 0", name: "questions_position_positive"
    t.check_constraint "points >= 1 AND points <= 1000", name: "questions_points_valid"
    t.check_constraint "time_limit_seconds = 0 OR time_limit_seconds >= 5 AND time_limit_seconds <= 300", name: "questions_time_limit_valid"
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
    t.string "google_uid", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "suspended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  add_foreign_key "activities", "uploaded_assets"
  add_foreign_key "activities", "users"
  add_foreign_key "activity_versions", "activities"
  add_foreign_key "attempts", "activity_versions"
  add_foreign_key "play_sessions", "activity_versions"
  add_foreign_key "questions", "activities"
  add_foreign_key "uploaded_assets", "users"
  add_foreign_key "user_sessions", "users"
end
