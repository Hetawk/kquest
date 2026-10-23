class PlaySession < ApplicationRecord
  AVATAR_IDS = %w[fox panda lion frog cat penguin tiger rabbit owl unicorn koala dragon].freeze
  DEFAULT_AVATAR_ID = "fox"

  belongs_to :activity_version
  belongs_to :game_room, optional: true

  validates :learner_name, presence: true, length: { maximum: 80 }
  validates :avatar_id, inclusion: { in: AVATAR_IDS }
  validates :start_key, format: { with: /\A[0-9a-f-]{36}\z/i }, uniqueness: true
  validates :submission_key, format: { with: /\A[0-9a-f-]{36}\z/i }, uniqueness: true
  validates :current_question_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
  validates :question_started_at, presence: true, unless: -> { completed? || game_room_id? }

  def completed?
    completed_at.present?
  end
end
