# frozen_string_literal: true

# Serializes a GamedbReleaseAnnouncement (all columns). The bot delivery columns
# (`sent_at`, `skipped_at`, `skip_reason`) are exposed read-only so a client can
# see delivery state — the controller strips them from create/update writes and
# sets the skip columns only via the dedicated skip action (#43).
class ReleaseAnnouncementResource
  include BaseResource

  columns_of GamedbReleaseAnnouncement
end
