# frozen_string_literal: true

# The consumer-audited collection allowlist (#36), shared by the user-scoped
# list (CollectionEntryResource), the game-scoped community-ownership list
# (CollectionUserEntryResource) and the full detail view
# (CollectionEntryDetailResource) of a UserGameCollection entry.
#
# The entry PK (`entry_id`), `user_id`, `gamedb_game_id`, `platform_id`,
# `ownership_type` and `note` are read. `platform_name` and
# `platform_abbreviation` are joined off the (optional) platform so the Discord
# bot can render and filter on the platform without a second
# `GET /api/v1/platforms/:id` (#101); both are null when the entry has no
# platform. `is_shared` (write-only input) and the timestamps are dropped here
# — the detail view re-adds them.
module CollectionFields
  extend ActiveSupport::Concern

  included do
    attributes :entry_id, :user_id, :gamedb_game_id, :platform_id, :ownership_type, :note
    attribute(:platform_name) { |entry| entry.platform&.platform_name }
    attribute(:platform_abbreviation) { |entry| entry.platform&.platform_abbreviation }
  end
end
