class AddLiveRoundReviewState < ActiveRecord::Migration[8.1]
  def change
    add_column :game_rooms, :round_phase, :string, null: false, default: "question"
    add_column :game_rooms, :closed_question_indices, :jsonb, null: false, default: []
    add_check_constraint(
      :game_rooms,
      "round_phase IN ('question', 'leaderboard', 'answer')",
      name: "game_rooms_round_phase_valid"
    )
  end
end
