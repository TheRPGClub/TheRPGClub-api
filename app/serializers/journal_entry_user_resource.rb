# frozen_string_literal: true

# A journal entry with its embedded author, for the game-scoped public list
# where entries from several users are interleaved and the game is already
# known from the route.
class JournalEntryUserResource
  include BaseResource
  include JournalFields

  one :user, resource: UserSummaryResource
end
