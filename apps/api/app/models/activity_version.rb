class ActivityVersion < ApplicationRecord
  CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  belongs_to :activity
  has_many :attempts, dependent: :restrict_with_error

  before_validation :assign_share_code, on: :create

  validates :version_number, numericality: { only_integer: true, greater_than: 0 },
                             uniqueness: { scope: :activity_id }
  validates :share_code, presence: true, uniqueness: true, length: { is: 12 }
  validates :question_snapshot, presence: true
  validates :published_at, presence: true
  validate :published_version_is_immutable, if: :persisted?

  private

  def assign_share_code
    return if share_code.present?

    self.share_code = Array.new(12) do
      CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)]
    end.join
  end

  def published_version_is_immutable
    errors.add(:base, "Published activity versions are immutable.")
  end
end
