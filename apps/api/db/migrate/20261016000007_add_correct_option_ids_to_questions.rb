class AddCorrectOptionIdsToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :correct_option_ids, :jsonb, null: false, default: []
  end
end
