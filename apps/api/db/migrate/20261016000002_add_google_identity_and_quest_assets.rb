class AddGoogleIdentityAndQuestAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |table|
      table.string :google_uid, null: false
      table.string :email, null: false
      table.string :name, null: false
      table.datetime :suspended_at
      table.timestamps
    end
    add_index :users, :google_uid, unique: true
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"

    create_table :user_sessions, id: :uuid do |table|
      table.references :user, null: false, type: :uuid, foreign_key: true
      table.string :token_digest, null: false
      table.datetime :expires_at, null: false
      table.datetime :revoked_at
      table.timestamps
    end
    add_index :user_sessions, :token_digest, unique: true

    create_table :uploaded_assets, id: :uuid do |table|
      table.references :user, null: false, type: :uuid, foreign_key: true
      table.string :provider_asset_id, null: false
      table.text :public_url, null: false
      table.string :content_type, null: false
      table.integer :file_size, null: false
      table.timestamps
    end
    add_index :uploaded_assets, :provider_asset_id, unique: true
    add_check_constraint :uploaded_assets, "file_size > 0", name: "uploaded_assets_positive_size"

    add_reference :activities, :user, type: :uuid, foreign_key: true
    add_reference :activities, :uploaded_asset, type: :uuid, foreign_key: true
    add_column :activity_versions, :cover_image_url, :text
  end
end
