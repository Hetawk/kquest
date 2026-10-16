class AddGroupGameRoomsAndQuestionShuffle < ActiveRecord::Migration[8.1]
  def change
    add_column :activities, :shuffle_questions, :boolean, null: false, default: false
    add_column :activities, :speed_scoring, :boolean, null: false, default: true
    add_column :attempts, :total_response_time_ms, :integer, null: false, default: 0

    create_table :game_rooms, id: :uuid do |table|
      table.references :activity_version, null: false, type: :uuid, foreign_key: true
      table.references :host_user, null: false, type: :uuid, foreign_key: { to_table: :users }
      table.string :room_code, null: false, limit: 12
      table.string :status, null: false, default: "waiting"
      table.integer :current_question_index, null: false, default: 0
      table.datetime :question_started_at
      table.datetime :ended_at
      table.timestamps
    end
    add_index :game_rooms, :room_code, unique: true
    add_reference :attempts, :game_room, type: :uuid, foreign_key: true
    add_index :attempts, [ :activity_version_id, :game_room_id, :score, :total_response_time_ms ],
      name: "index_attempts_on_leaderboard"
    add_check_constraint(
      :game_rooms,
      "status IN ('waiting', 'active', 'completed')",
      name: "game_rooms_status_valid"
    )
    add_check_constraint(
      :game_rooms,
      "current_question_index >= 0",
      name: "game_rooms_question_index_nonnegative"
    )
    add_reference :play_sessions, :game_room, type: :uuid, foreign_key: true
    add_index :play_sessions, [ :game_room_id, :start_key ], unique: true
  end
end
