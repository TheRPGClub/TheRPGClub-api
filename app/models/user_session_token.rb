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

  # The member an active token belongs to, read with it in one query and
  # without the avatar/profile image bytes (RpgClubUser.without_images): auth
  # runs on every signed-in request. The token's flags come back as the
  # `session_is_dev` / `session_is_longstanding` attributes. nil for a blank,
  # unknown or expired token.
  def self.authenticated_user(raw_token)
    return nil if raw_token.blank?

    RpgClubUser
      .select(*RpgClubUser.qualified_columns_without_images,
        "user_session_tokens.is_dev AS session_is_dev",
        "user_session_tokens.is_longstanding AS session_is_longstanding")
      .joins("INNER JOIN user_session_tokens ON user_session_tokens.user_id = rpg_club_users.user_id")
      .where(user_session_tokens: { token: Digest::SHA256.hexdigest(raw_token) })
      .where("user_session_tokens.expires_at > ?", Time.current)
      .first
  end
end
