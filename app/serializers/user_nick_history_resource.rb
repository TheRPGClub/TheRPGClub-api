# frozen_string_literal: true

# Serializes an RpgClubUserNickHistory row (all columns, read-only) — #49.
class UserNickHistoryResource
  include BaseResource

  columns_of RpgClubUserNickHistory
end
