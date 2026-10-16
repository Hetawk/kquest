class AddSpeedBonusPointsToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :speed_bonus_points, :integer, default: 100, null: false
    add_check_constraint :questions,
      "speed_bonus_points >= 0 AND speed_bonus_points <= 100000",
      name: "questions_speed_bonus_points_valid"
  end
end
