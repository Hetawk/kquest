class GameRoom < ApplicationRecord
  STATUSES = %w[waiting active completed].freeze
  ROUND_PHASES = %w[question leaderboard answer].freeze

  belongs_to :activity_version
  belongs_to :host_user, class_name: "User"
  has_many :play_sessions, dependent: :destroy

  before_validation :assign_room_code, on: :create

  validates :room_code, presence: true, uniqueness: true, length: { is: ActivityVersion::CODE_LENGTH }
  validates :status, inclusion: { in: STATUSES }
  validates :round_phase, inclusion: { in: ROUND_PHASES }
  validates :current_question_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :room_code_is_not_used_by_an_activity

  private

  def assign_room_code
    return if room_code.present?

    loop do
      self.room_code = Array.new(ActivityVersion::CODE_LENGTH) do
        ActivityVersion::CODE_ALPHABET[
          SecureRandom.random_number(ActivityVersion::CODE_ALPHABET.length)
        ]
      end.join
      break unless ActivityVersion.exists?(share_code: room_code) || self.class.exists?(room_code: room_code)
    end
  end

  def room_code_is_not_used_by_an_activity
    return if room_code.blank? || !ActivityVersion.exists?(share_code: room_code)

    errors.add(:room_code, "is already in use.")
  end
end
