class Activity < ApplicationRecord
  MAX_QUESTIONS = 100
  STATUSES = %w[draft published].freeze

  belongs_to :user, optional: true
  belongs_to :uploaded_asset, optional: true
  has_many :questions, -> { order(:position) }, dependent: :destroy
  has_many :activity_versions, dependent: :restrict_with_error
  has_many :game_rooms, through: :activity_versions

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 500 }
  validates :status, inclusion: { in: STATUSES }
  validate :published_content_is_immutable, if: :persisted?
  validate :question_count_within_limit

  private

  def published_content_is_immutable
    return unless status_in_database == "published"

    errors.add(:base, "Published activities cannot be edited.")
  end

  def question_count_within_limit
    return if questions.size <= MAX_QUESTIONS

    errors.add(:questions, "cannot exceed #{MAX_QUESTIONS} questions.")
  end
end
