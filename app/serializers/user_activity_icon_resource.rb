# frozen_string_literal: true

# Serializes an RpgClubUserActivityIcon row (all columns, read-only) — #46.
class UserActivityIconResource
  include BaseResource

  columns_of RpgClubUserActivityIcon
end
