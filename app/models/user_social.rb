# frozen_string_literal: true

class UserSocial < ApplicationRecord
  self.table_name = "user_socials"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :socials

  belongs_to :social_platform,
    foreign_key: :platform_id,
    inverse_of: :user_socials

  before_validation :normalize_fields

  validates :user_id, presence: true

  # `display_text` is a free, optional label — it legitimately repeats ("Profile
  # Link", "Steam"), so it carries no uniqueness (TheRPGClub#80). Identity lives
  # on the URL instead: one account per URL within a (user, platform). Blank URLs
  # (PSN, Switch friend code, etc.) skip the check, mirroring the partial unique
  # index `index_user_socials_on_user_platform_url` (`WHERE url IS NOT NULL`).
  validates :url, uniqueness: { scope: %i[user_id platform_id], case_sensitive: false },
                  allow_blank: true

  private

  def normalize_fields
    self.url = url.to_s.strip.presence
    self.display_text = display_text.to_s.strip.presence
  end
end
