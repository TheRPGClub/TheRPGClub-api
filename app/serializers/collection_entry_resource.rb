# frozen_string_literal: true

# Serializes a UserGameCollection entry for the user-scoped list
# (collections#index). The consumer-audited column set plus the joined platform
# name/abbreviation live in CollectionFields (#36, #101).
class CollectionEntryResource
  include BaseResource
  include CollectionFields
end
