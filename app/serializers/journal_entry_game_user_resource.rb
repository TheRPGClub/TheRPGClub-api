# frozen_string_literal: true

# A journal entry with BOTH its embedded game and author, for the cross-user
# search list (JournalController#search) where entries from several users and
# games are interleaved and neither context is known from the route. Mirrors
# the bot's `searchJournalEntries`, which returns each row with its game title
# and author names.
class JournalEntryGameUserResource
  include BaseResource
  include JournalFields

  one :game, resource: GameSummaryResource
  one :user, resource: UserSummaryResource
end
