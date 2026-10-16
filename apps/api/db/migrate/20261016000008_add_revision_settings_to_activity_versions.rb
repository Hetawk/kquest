class AddRevisionSettingsToActivityVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :activity_versions, :shuffle_questions, :boolean, null: false, default: false
    add_column :activity_versions, :speed_scoring, :boolean, null: false, default: true

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE activity_versions
          SET shuffle_questions = activities.shuffle_questions,
              speed_scoring = activities.speed_scoring
          FROM activities
          WHERE activities.id = activity_versions.activity_id
        SQL
      end
    end
  end
end
