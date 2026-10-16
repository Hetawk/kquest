class User < ApplicationRecord
  has_secure_password validations: false

  has_many :game_rooms, foreign_key: :host_user_id, dependent: :restrict_with_error
  has_many :activities, dependent: :restrict_with_error
  has_many :user_sessions, dependent: :destroy
  has_many :uploaded_assets, dependent: :restrict_with_error

  validates :google_uid, uniqueness: true, allow_nil: true
  validates :email, presence: true, length: { maximum: 320 },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 160 }
  before_validation :normalize_email
  validate :has_authentication_method
  validate :password_strength

  def active?
    suspended_at.nil?
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def has_authentication_method
    errors.add(:base, "An authentication method is required.") if google_uid.blank? && password_digest.blank?
  end

  def password_strength
    return if password.blank?

    errors.add(:password, "must be at least 12 characters") if password.length < 12
    errors.add(:password, "must be no more than 72 bytes") if password.bytesize > 72
  end
end
