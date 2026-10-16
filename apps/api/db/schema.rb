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

ActiveRecord::Schema[8.1].define(version: 2026_10_16_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title", limit: 120, null: false
    t.text "description", default: "", null: false
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text])", name: "activities_status_valid"
  end

  create_table "activity_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "activity_id", null: false
    t.integer "version_number", null: false
    t.string "share_code", limit: 12, null: false
    t.jsonb "question_snapshot", default: [], null: false
    t.datetime "published_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["activity_id", "position"], name: "index_questions_on_activity_id_and_position", unique: true
    t.index ["activity_id"], name: "index_questions_on_activity_id"
    t.check_constraint "\"position\" > 0", name: "questions_position_positive"
    t.check_constraint "points >= 1 AND points <= 1000", name: "questions_points_valid"
  end

  add_foreign_key "activity_versions", "activities"
  add_foreign_key "attempts", "activity_versions"
  add_foreign_key "questions", "activities"
end
