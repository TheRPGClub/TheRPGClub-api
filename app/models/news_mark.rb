# frozen_string_literal: true

# The News Mark (GLOSSARY.md, "News Hub"; spec api#494, ticket api#495): the
# moment up to which a member has seen the News Hub's News Items, kept on the
# member's RpgClubUser row (news_mark_at). It is per member and set only by
# the website; it is never per-item read state.
#
# It only moves forward: a later instant moves it, an earlier one keeps the
# stored mark, and an instant past now is clamped to now.
module NewsMark
  module_function

  # The member's News Mark, or nil when they have none yet.
  def for(user_id)
    RpgClubUser.where(user_id: user_id).pick(:news_mark_at)
  end

  # Moves the member's News Mark forward to `instant` (clamped to now) and
  # returns the stored mark (nil when the API has no row for the member). One UPDATE, so two requests at once (a beacon
  # racing Mark all seen) still never move it backwards.
  def advance!(user_id, instant, now: Time.current)
    to = [ instant, now ].min
    RpgClubUser.where(user_id: user_id)
      .update_all([ "news_mark_at = GREATEST(COALESCE(news_mark_at, :to), :to)", { to: to } ])
    self.for(user_id)
  end
end
