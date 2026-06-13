# frozen_string_literal: true

# Serializes a GamedbCollection (a game's "series").
#
# Consumer-audited allowlist: the Discord bot's game profile needs the series
# name (and its id to link), so `collection_id` and `name` are exposed. The
# IGDB sync bookkeeping column (`igdb_collection_id`) is internal and read by no
# consumer, so it is dropped from output — mirroring PlatformResource (#36).
class CollectionResource
  include BaseResource

  attributes :collection_id, :name
end
