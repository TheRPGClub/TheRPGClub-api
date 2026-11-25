# frozen_string_literal: true

# Serializes a UserGameCollection entry for the user-scoped list
# (collections#index). The consumer-audited column set plus the joined platform
# name/abbreviation live in CollectionFields (#36, #101). The list also embeds
# the game and the platform so the web shelves need no per-entry game fetch;
# the flat `platform_name` / `platform_abbreviation` stay because the Discord
# bot reads them. `added_at` is the entry's `created_at` (the profile's lift
# tags, spec api#457).
class CollectionEntryResource
  include BaseResource
  include ShelfPlaytimeFields.with
  include CollectionFields

  attribute(:added_at, &:created_at)
  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
