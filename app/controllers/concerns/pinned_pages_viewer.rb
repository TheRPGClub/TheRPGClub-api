# frozen_string_literal: true

# The signed-in member as a PinnedPages::Viewer: their Feature access (as the
# session's `features` decide it) and their staff tiers from StaffGates. For
# the Pinned Pages endpoints and the session payload. `access` is the
# viewer's Features::Access (pinned_access builds it), so a caller that also
# needs it builds it once.
module PinnedPagesViewer
  extend ActiveSupport::Concern

  private

  # `user` is the member's record, nil when they have none.
  def pinned_access(user) = Features::Access.for_viewer(user, staff: admin_or_above?)

  def pinned_viewer(access)
    PinnedPages::Viewer.new(
      access: access,
      moderator: moderator_or_above?, admin: admin_or_above?, superadmin: superadmin?
    )
  end
end
