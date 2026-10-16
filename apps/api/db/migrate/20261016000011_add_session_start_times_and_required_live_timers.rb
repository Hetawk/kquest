class AddSessionStartTimesAndRequiredLiveTimers < ActiveRecord::Migration[8.1]
  def up
    add_column :attempts, :started_at, :datetime, precision: 6
    add_column :game_rooms, :started_at, :datetime, precision: 6
    add_column :game_rooms, :question_start_times, :jsonb, null: false, default: {}

    execute "UPDATE questions SET time_limit_seconds = 30 WHERE time_limit_seconds = 0"

    add_check_constraint(
      :questions,
      "time_limit_seconds BETWEEN 5 AND 300",
      name: "questions_time_limit_seconds_valid"
    )
  end

  def down
    remove_check_constraint :questions, name: "questions_time_limit_seconds_valid"
    remove_column :game_rooms, :question_start_times
    remove_column :game_rooms, :started_at
    remove_column :attempts, :started_at
  end
end
