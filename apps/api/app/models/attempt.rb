class Attempt < ApplicationRecord
  belongs_to :activity_version

  validates :learner_name, presence: true, length: { maximum: 80 }
  validates :submission_key, presence: true, uniqueness: true,
                             format: { with: /\A[0-9a-f-]{36}\z/i }
  validates :responses, presence: true
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_score, numericality: { only_integer: true, greater_than: 0 }
  validates :submitted_at, presence: true
  validate :score_does_not_exceed_maximum

  private

  def score_does_not_exceed_maximum
    return if score.nil? || max_score.nil? || score <= max_score

    errors.add(:score, "must not exceed the maximum score")
  end
end
