class CreateLearningJourney < ActiveRecord::Migration[8.1]
  def change
    create_table :activities, id: :uuid do |table|
      table.string :title, null: false, limit: 120
      table.text :description, null: false, default: "", limit: 500
      table.string :status, null: false, default: "draft"
      table.timestamps
    end

    add_check_constraint :activities, "status IN ('draft', 'published')", name: "activities_status_valid"

    create_table :questions, id: :uuid do |table|
      table.references :activity, null: false, type: :uuid, foreign_key: true
      table.integer :position, null: false
      table.string :question_type, null: false, default: "single_choice"
      table.text :prompt, null: false, limit: 500
      table.jsonb :options, null: false, default: []
      table.string :correct_option_id, null: false
      table.integer :points, null: false, default: 100
      table.timestamps
    end

    add_index :questions, [ :activity_id, :position ], unique: true
    add_check_constraint :questions, "position > 0", name: "questions_position_positive"
    add_check_constraint :questions, "points BETWEEN 1 AND 1000", name: "questions_points_valid"

    create_table :activity_versions, id: :uuid do |table|
      table.references :activity, null: false, type: :uuid, foreign_key: true
      table.integer :version_number, null: false
      table.string :share_code, null: false, limit: 12
      table.jsonb :question_snapshot, null: false, default: []
      table.datetime :published_at, null: false
      table.timestamps
    end

    add_index :activity_versions, [ :activity_id, :version_number ], unique: true
    add_index :activity_versions, :share_code, unique: true

    create_table :attempts, id: :uuid do |table|
      table.references :activity_version, null: false, type: :uuid, foreign_key: true
      table.string :learner_name, null: false, limit: 80
      table.string :submission_key, null: false, limit: 36
      table.jsonb :responses, null: false, default: []
      table.integer :score, null: false
      table.integer :max_score, null: false
      table.datetime :submitted_at, null: false
      table.timestamps
    end

    add_index :attempts, :submission_key, unique: true
    add_index :attempts, [ :activity_version_id, :submitted_at ]
    add_check_constraint :attempts, "score >= 0 AND score <= max_score", name: "attempts_score_valid"
    add_check_constraint :attempts, "max_score > 0", name: "attempts_max_score_positive"
  end
end
