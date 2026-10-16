require "set"

class ShortenGameCodes < ActiveRecord::Migration[8.1]
  ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def up
    rotate_codes(length: 6)
    change_column :activity_versions, :share_code, :string, limit: 6, null: false
    change_column :game_rooms, :room_code, :string, limit: 6, null: false
  end

  def down
    change_column :activity_versions, :share_code, :string, limit: 12, null: false
    change_column :game_rooms, :room_code, :string, limit: 12, null: false
    rotate_codes(length: 12)
  end

  private

  def rotate_codes(length:)
    used_codes = select_values(<<~SQL).to_set
      SELECT share_code FROM activity_versions
      UNION
      SELECT room_code FROM game_rooms
    SQL

    [ [ :activity_versions, :share_code ], [ :game_rooms, :room_code ] ].each do |table, column|
      select_values("SELECT id FROM #{table} ORDER BY id").each do |id|
        code = generate_code(length, used_codes)
        execute(
          "UPDATE #{table} SET #{column} = #{connection.quote(code)} " \
          "WHERE id = #{connection.quote(id)}"
        )
      end
    end
  end

  def generate_code(length, used_codes)
    loop do
      code = Array.new(length) do
        ALPHABET[SecureRandom.random_number(ALPHABET.length)]
      end.join
      return code if used_codes.add?(code)
    end
  end
end
