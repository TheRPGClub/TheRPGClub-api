# frozen_string_literal: true

# A UserGameCollection with its embedded user, for the game-scoped collections
# list (collections#game_index, the community-ownership view, #101): the
# CollectionFields columns plus the joined platform name/abbreviation and the
# `user` summary (without binary image blobs). Mirrors CompletionUserEntryResource.
class CollectionUserEntryResource
  include BaseResource
  include CollectionFields

  one :user, resource: UserSummaryResource
end
