# frozen_string_literal: true

# The signed-in member as a PinnedPages::Viewer: their Feature access (as the
# session's `features` decide it) and their staff tiers from StaffGates. For
# the Pinned Pages endpoints and the session payload. `user` is the member's
# record, nil when they have none.
module PinnedPagesViewer
  extend ActiveSupport::Concern

  private

  def pinned_viewer(user)
    PinnedPages::Viewer.new(
      access: Features::Access.for_viewer(user, staff: admin_or_above?),
      moderator: moderator_or_above?, admin: admin_or_above?, superadmin: superadmin?
    )
  end
end
