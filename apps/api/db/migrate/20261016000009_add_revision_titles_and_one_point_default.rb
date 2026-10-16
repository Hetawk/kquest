class AddRevisionTitlesAndOnePointDefault < ActiveRecord::Migration[8.1]
  def up
    add_column :activity_versions, :title, :string, limit: 120
    execute <<~SQL
      UPDATE activity_versions
      SET title = activities.title
      FROM activities
      WHERE activities.id = activity_versions.activity_id
    SQL
    change_column_null :activity_versions, :title, false
    change_column_default :questions, :points, from: 100, to: 1
  end

  def down
    change_column_default :questions, :points, from: 1, to: 100
    remove_column :activity_versions, :title
  end
end
