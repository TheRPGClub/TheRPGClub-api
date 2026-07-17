# frozen_string_literal: true

# The full RpgClubCollectionCsvImport record (#163): every column, matching
# the documented "full record" contract used by the other job-style resources
# (e.g. WizardSessionResource).
class CollectionCsvImportResource
  include BaseResource
  columns_of RpgClubCollectionCsvImport
end
