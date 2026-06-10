# frozen_string_literal: true

# Serializes an RpgClubUserChannelCount row (all columns, read-only) — #47.
class UserChannelCountResource
  include BaseResource

  columns_of RpgClubUserChannelCount
end
