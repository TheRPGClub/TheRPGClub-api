# frozen_string_literal: true

# A Hidden Platform (GLOSSARY.md; spec api#421, ticket api#427): one row per
# platform a member leaves out of their own Release Calendar and Upcoming
# Releases panel. Rows are written only through HiddenPlatformsController,
# which replaces a member's whole set at once.
class MemberHiddenPlatform < ApplicationRecord
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
  belongs_to :platform, class_name: "GamedbPlatform", primary_key: :platform_id, inverse_of: false

  # The member's Hidden Platform ids, in no particular order.
  def self.platform_ids_for(user_id)
    where(user_id: user_id.to_s).pluck(:platform_id)
  end
end
