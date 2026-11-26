# frozen_string_literal: true

# The Patch Mark (spec api#510, ticket api#512): the number of the newest
# Patch a member has seen, kept on the member's RpgClubUser row
# (patch_mark). It is per member, so it is the same on every device, and set
# only by the website when the member opens /patch-notes or a Patch page.
#
# It only moves forward: a higher number moves it, a lower one keeps the
# stored mark, and a number past the newest published Patch is clamped to
# that Patch, so a draft published later still reads as unseen.
module PatchMark
  module_function

  # The member's Patch Mark, or nil when they have none yet.
  def for(user_id)
    RpgClubUser.where(user_id: user_id).pick(:patch_mark)
  end

  # Whether a published Patch is newer than `mark` (nil: none seen yet, so
  # any published Patch is unseen).
  def unseen?(mark)
    Patch.published.where(number: (mark.to_i + 1)..).exists?
  end

  # Moves the member's Patch Mark forward to `number` (clamped to the newest
  # published Patch) and returns the stored mark. With no published Patch the
  # mark stays as it is. Creates the member's row first, as the other member
  # documents do. One UPDATE, so two requests at once never move it
  # backwards.
  def advance!(user_id, number)
    to = [ number, Patch.published.maximum(:number) ].compact.min if Patch.published.exists?
    if to
      RpgClubUser.find_or_create_by!(user_id: user_id)
      RpgClubUser.where(user_id: user_id)
        .update_all([ "patch_mark = GREATEST(COALESCE(patch_mark, :to), :to)", { to: to } ])
    end
    self.for(user_id)
  end
end
