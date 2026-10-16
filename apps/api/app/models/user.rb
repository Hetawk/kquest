class User < ApplicationRecord
  has_many :game_rooms, foreign_key: :host_user_id, dependent: :restrict_with_error
  has_many :activities, dependent: :restrict_with_error
  has_many :user_sessions, dependent: :destroy
  has_many :uploaded_assets, dependent: :restrict_with_error

  validates :google_uid, presence: true, uniqueness: true
  validates :email, presence: true, length: { maximum: 320 }
  validates :name, presence: true, length: { maximum: 160 }

  def active?
    suspended_at.nil?
  end
end
