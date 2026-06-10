# frozen_string_literal: true

# Serializes a ThreadGameLink (all columns: thread_id, gamedb_game_id,
# linked_at). Embedded under `links` on the thread show response and returned
# from the link create endpoint.
class ThreadGameLinkResource
  include BaseResource

  columns_of ThreadGameLink
end
