# frozen_string_literal: true

# The full SteamCollectionImportItem record (#166): every column, so the bot
# can read back both the raw Steam app/playtime fields and the resolved
# match / outcome in one call.
class SteamCollectionImportItemResource
  include BaseResource
  columns_of RpgClubSteamCollectionImportItem
end
