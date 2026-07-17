# frozen_string_literal: true

# The full RpgClubCollectionCsvImportItem record (#163): every column, so the
# bot can read back both the raw parsed CSV fields and the resolved match /
# outcome in one call.
class CollectionCsvImportItemResource
  include BaseResource
  columns_of RpgClubCollectionCsvImportItem
end
