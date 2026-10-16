class ActivityVersion < ApplicationRecord
  CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  CODE_LENGTH = 6
  CODE_REGEX = /\A[A-HJ-NP-Z2-9]{#{CODE_LENGTH}}\z/

  belongs_to :activity
  has_many :attempts, dependent: :restrict_with_error
  has_many :play_sessions, dependent: :delete_all
  has_many :game_rooms, dependent: :restrict_with_error

  before_validation :assign_share_code, on: :create

  validates :version_number, numericality: { only_integer: true, greater_than: 0 },
                             uniqueness: { scope: :activity_id }
  validates :title, presence: true, length: { maximum: 120 }
  validates :share_code, presence: true, uniqueness: true, length: { is: CODE_LENGTH }
  validates :question_snapshot, presence: true
  validates :published_at, presence: true
  validates :shuffle_questions, inclusion: { in: [ true, false ] }
  validates :speed_scoring, inclusion: { in: [ true, false ] }
  validate :published_version_is_immutable, if: :persisted?
  validate :share_code_is_not_used_by_a_room

  private

  def assign_share_code
    return if share_code.present?

    loop do
      self.share_code = Array.new(CODE_LENGTH) do
        CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)]
      end.join
      break unless GameRoom.exists?(room_code: share_code) || self.class.exists?(share_code: share_code)
    end
  end

  def share_code_is_not_used_by_a_room
    return if share_code.blank? || !GameRoom.exists?(room_code: share_code)

    errors.add(:share_code, "is already in use.")
  end

  def published_version_is_immutable
    errors.add(:base, "Published activity versions are immutable.")
  end
end
