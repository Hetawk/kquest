class AddLearnerCharacterToPlaySessions < ActiveRecord::Migration[8.1]
  def change
    add_column :play_sessions, :avatar_id, :string, null: false, default: "fox"
    add_check_constraint(
      :play_sessions,
      "avatar_id IN ('fox', 'panda', 'lion', 'frog', 'cat', 'penguin', 'tiger', 'rabbit', 'owl', 'unicorn', 'koala', 'dragon')",
      name: "play_sessions_avatar_id_valid"
    )
  end
end
