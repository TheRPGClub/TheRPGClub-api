# frozen_string_literal: true

# A member who owns a game in their collection, for the aggregate game profile's
# `collection_owners` list (#115): just the identity (`user_id` + `username`).
# Folds in the `GET /api/v1/games/:id/collections` need flagged in the bot-side
# consolidation, sparing the bot a direct-SQL read.
#
# Backed by UserGameCollection rows; callers dedupe by `user_id` first (a member
# may own the same game on several platforms). The `user` association is
# optional, so `username` is null when it doesn't resolve.
class CollectionOwnerResource
  include BaseResource

  attributes :user_id
  attribute(:username) { |entry| entry.user&.username }
end
