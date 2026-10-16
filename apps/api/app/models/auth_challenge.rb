class AuthChallenge < ApplicationRecord
  MAX_ATTEMPTS = 5
  CODE_LIFETIME = 10.minutes
  RESEND_INTERVAL = 60.seconds
  HOURLY_SEND_LIMIT = 5

  belongs_to :user, optional: true

  validates :email, :purpose, :code_digest, :expires_at, :last_sent_at, presence: true
  validates :purpose, inclusion: { in: %w[email_verification password_reset] }
  validates :attempts, numericality: { only_integer: true, in: 0..MAX_ATTEMPTS }

  class RateLimited < StandardError; end
  class ResendTooSoon < StandardError; end

  scope :active, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(email:, purpose:, user: nil)
    normalized_email = email.to_s.strip.downcase
    now = Time.current

    recent = where(email: normalized_email, purpose:, created_at: 1.hour.ago..)
      .order(created_at: :desc)
    raise RateLimited if recent.count >= HOURLY_SEND_LIMIT
    raise ResendTooSoon if recent.where("last_sent_at > ?", RESEND_INTERVAL.ago).exists?

    code = format("%06d", SecureRandom.random_number(1_000_000))
    challenge = nil
    transaction do
      active.where(email: normalized_email, purpose:).update_all(consumed_at: now, updated_at: now)
      challenge = create!(
        user:,
        email: normalized_email,
        purpose:,
        code_digest: digest(code),
        expires_at: now + CODE_LIFETIME,
        last_sent_at: now
      )
      where("created_at < ?", 1.day.ago).delete_all
    end
    [ challenge, code ]
  end

  def consume_if_valid!(code)
    with_lock do
      return false if consumed_at? || expires_at <= Time.current || attempts >= MAX_ATTEMPTS

      self.attempts += 1
      valid = ActiveSupport::SecurityUtils.secure_compare(code_digest, self.class.digest(code.to_s))
      self.consumed_at = Time.current if valid
      save!
      valid
    end
  end

  def self.digest(code)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code)
  end
end
