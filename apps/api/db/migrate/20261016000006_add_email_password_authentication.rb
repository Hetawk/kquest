class AddEmailPasswordAuthentication < ActiveRecord::Migration[8.1]
  def up
    change_column_null :users, :google_uid, true
    add_column :users, :password_digest, :string
    add_column :users, :email_verified_at, :datetime

    execute <<~SQL
      UPDATE users
      SET email_verified_at = created_at
      WHERE google_uid IS NOT NULL AND email_verified_at IS NULL
    SQL

    create_table :auth_challenges, id: :uuid do |table|
      table.references :user, type: :uuid, foreign_key: true
      table.string :email, null: false
      table.string :purpose, null: false
      table.string :code_digest, null: false
      table.datetime :expires_at, null: false
      table.datetime :consumed_at
      table.datetime :last_sent_at, null: false
      table.integer :attempts, null: false, default: 0
      table.timestamps
    end
    add_index :auth_challenges, [ :email, :purpose, :created_at ]
    add_index :auth_challenges, :expires_at
    add_check_constraint :auth_challenges, "attempts >= 0 AND attempts <= 5",
      name: "auth_challenges_attempts_range"
  end

  def down
    drop_table :auth_challenges
    remove_column :users, :email_verified_at
    remove_column :users, :password_digest
    change_column_null :users, :google_uid, false
  end
end
