class AddTimedPlaySessions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :time_limit_seconds, :integer, null: false, default: 30
    add_check_constraint(
      :questions,
      "time_limit_seconds = 0 OR time_limit_seconds BETWEEN 5 AND 300",
      name: "questions_time_limit_valid"
    )

    create_table :play_sessions, id: :uuid do |table|
      table.references :activity_version, null: false, type: :uuid, foreign_key: true
      table.string :learner_name, null: false, limit: 80
      table.string :start_key, null: false, limit: 36
      table.string :submission_key, null: false, limit: 36
      table.integer :current_question_index, null: false, default: 0
      table.jsonb :responses, null: false, default: []
      table.datetime :question_started_at
      table.datetime :expires_at, null: false
      table.datetime :completed_at
      table.string :last_request_key, limit: 36
      table.string :last_request_fingerprint, limit: 64
      table.jsonb :last_response
      table.timestamps
    end
    add_index :play_sessions, :start_key, unique: true
    add_index :play_sessions, :submission_key, unique: true
    add_index :play_sessions, :expires_at
    add_check_constraint(
      :play_sessions,
      "current_question_index >= 0",
      name: "play_sessions_question_index_nonnegative"
    )
  end
end
