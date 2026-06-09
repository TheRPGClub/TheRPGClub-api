# frozen_string_literal: true

# A journal entry with its embedded game, for the single-entry endpoints
# (show/create/update) where the game context is useful and the author is
# already known from `user_id`.
class JournalEntryGameResource
  include BaseResource
  include JournalFields

  one :game, resource: GameSummaryResource
end
