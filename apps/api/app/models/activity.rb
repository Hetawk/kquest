class Activity < ApplicationRecord
  STATUSES = %w[draft published].freeze

  has_many :questions, -> { order(:position) }, dependent: :destroy
  has_many :activity_versions, dependent: :restrict_with_error

  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 500 }
  validates :status, inclusion: { in: STATUSES }
  validate :published_content_is_immutable, if: :persisted?

  private

  def published_content_is_immutable
    return unless status_in_database == "published"

    errors.add(:base, "Published activities cannot be edited.")
  end
end
