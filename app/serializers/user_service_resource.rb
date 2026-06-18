# frozen_string_literal: true

# The service-managed user shape (#105). Extends the consumer-audited
# UserSummary (UserFields) with the three Discord-sync columns the bot reads
# and writes via the member-sync endpoints: `server_joined_at`, `last_seen_at`
# and `emoji_name`.
#
# Returned by the service-only `users#upsert`/`users#update` writes (so the bot
# can confirm what it just synced) and by the `has_emoji_name` filtered index
# branch (UserEmojiService needs each user's current `emoji_name` to detect
# display-name drift). `server_left_at` (the departure marker) already comes
# from UserFields.
class UserServiceResource
  include BaseResource
  include UserFields

  attributes :server_joined_at, :last_seen_at, :emoji_name
end
