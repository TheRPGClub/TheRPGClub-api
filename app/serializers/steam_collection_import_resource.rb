# frozen_string_literal: true

# The full SteamCollectionImport record (#166): every column, matching the
# documented "full record" contract used by the other job-style resources
# (e.g. CollectionCsvImportResource).
class SteamCollectionImportResource
  include BaseResource
  columns_of RpgClubSteamCollectionImport
end
