class UploadedAsset < ApplicationRecord
  belongs_to :user
  has_many :activities, dependent: :restrict_with_error

  validates :provider_asset_id, presence: true, uniqueness: true
  validates :public_url, presence: true
  validates :content_type, inclusion: { in: %w[image/jpeg image/png image/webp] }
  validates :file_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 5.megabytes }
end
