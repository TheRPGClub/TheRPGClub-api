# frozen_string_literal: true

# The full UserGameCollection record for the detail endpoints
# (collections#show / create / update): the CollectionFields columns plus the
# joined platform name/abbreviation, plus `is_shared` and the timestamps the
# list trims. Replaces the prior `record.as_json` so the joined platform fields
# are included (#101) while preserving the documented "full record (all
# columns)" contract.
class CollectionEntryDetailResource
  include BaseResource
  include CollectionFields

  attributes :is_shared, :created_at, :updated_at
end
