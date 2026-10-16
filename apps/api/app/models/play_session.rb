class PlaySession < ApplicationRecord
  belongs_to :activity_version

  validates :learner_name, presence: true, length: { maximum: 80 }
  validates :start_key, format: { with: /\A[0-9a-f-]{36}\z/i }, uniqueness: true
  validates :submission_key, format: { with: /\A[0-9a-f-]{36}\z/i }, uniqueness: true
  validates :current_question_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
  validates :question_started_at, presence: true, unless: :completed?

  def completed?
    completed_at.present?
  end
end
