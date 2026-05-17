# frozen_string_literal: true

class UserSessionToken < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.generate_for(user, is_dev: false, is_longstanding: false)
    where(user_id: user.user_id).where("expires_at <= ?", Time.current).delete_all

    raw_token = SecureRandom.urlsafe_base64(32)
    create!(
      token: Digest::SHA256.hexdigest(raw_token),
      user_id: user.user_id,
      expires_at: 7.days.from_now,
      is_dev: is_dev,
      is_longstanding: is_longstanding
    )
    raw_token
  end

  def self.find_valid(raw_token)
    return nil if raw_token.blank?

    active.find_by(token: Digest::SHA256.hexdigest(raw_token))
  end
end
