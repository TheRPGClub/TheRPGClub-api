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

  # An ISO 8601 date and time that names its offset (`Z` or `+hh:mm`).
  INSTANT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})\z/i

  # The instant `value` names, from an ISO 8601 string with an offset.
  # Raises ArgumentError for anything else, including a time without an
  # offset, which would otherwise be read in the server's zone.
  def parse_instant(value)
    text = value.is_a?(String) ? value.strip : ""
    raise ArgumentError, "not an ISO 8601 instant with an offset" unless text.match?(INSTANT)

    Time.iso8601(text)
  end

  # The member's News Mark, or nil when they have none yet.
  def for(user_id)
    RpgClubUser.where(user_id: user_id).pick(:news_mark_at)
  end

  # Moves the member's News Mark forward to `instant` (clamped to now) and
  # returns the stored mark. Creates the member's row first, as the other
  # member documents do, so the mark is never dropped. One UPDATE, so two
  # requests at once (a beacon racing Mark all seen) still never move it
  # backwards.
  def advance!(user_id, instant, now: Time.current)
    to = [ instant, now ].min
    RpgClubUser.find_or_create_by!(user_id: user_id)
    RpgClubUser.where(user_id: user_id)
      .update_all([ "news_mark_at = GREATEST(COALESCE(news_mark_at, :to), :to)", { to: to } ])
    self.for(user_id)
  end
end
