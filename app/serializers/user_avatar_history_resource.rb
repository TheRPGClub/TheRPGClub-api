# frozen_string_literal: true

# Serializes an RpgClubUserAvatarHistory row (#105). All columns except the
# binary `avatar_blob` — clients fetch the rendered image from the CDN/avatar
# URL, never the raw bytes off this log.
class UserAvatarHistoryResource
  include BaseResource

  columns_of RpgClubUserAvatarHistory, except: %w[avatar_blob]
end
