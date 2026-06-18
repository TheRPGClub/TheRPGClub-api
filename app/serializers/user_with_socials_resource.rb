# frozen_string_literal: true

# The members-list user shape (UserSummaryResource / UserFields) plus the
# embedded `socials` list. Served by users#index when the request filters by
# `has_platform`, so the bot's `/mp-info` migration receives each matched
# user's platform handles/URLs in one call (#99) instead of a follow-up
# per-user socials fetch. Expects `socials` (with `social_platform`) loaded.
class UserWithSocialsResource
  include BaseResource
  include UserFields

  many :socials, resource: UserSocialResource
end
