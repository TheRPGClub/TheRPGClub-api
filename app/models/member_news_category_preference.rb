# frozen_string_literal: true

# A News Category Preference (GLOSSARY.md, "News Hub"; spec #355, ticket
# #357): one row per member per News Category they switched off. Only
# switched-off categories are stored, so every News Category is in a member's
# default view to begin with. A preference only shapes the News Hub feed's
# default result (no category filter); it never blocks a request and has no
# effect in Discord.
class MemberNewsCategoryPreference < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false

  validates :category_key, inclusion: { in: NewsCategory.keys, message: "is not a News Category" },
    uniqueness: { scope: :user_id }

  # The News Category keys `user_id` switched off, in News Category order. A
  # stored key that is no longer a News Category is ignored.
  def self.hidden_keys(user_id)
    return [] if user_id.blank?

    stored = where(user_id: user_id).pluck(:category_key)
    NewsCategory.keys & stored
  end
end
