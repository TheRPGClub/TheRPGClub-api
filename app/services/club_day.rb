# frozen_string_literal: true

# The club day (GLOSSARY.md, "club day"): a calendar day in the club's time
# zone, America/New_York, the one voting is scheduled in. Challenges,
# Birth Dates and Birthdays all count days this way.
module ClubDay
  TIME_ZONE = Voting::Schedule::TIME_ZONE

  module_function

  # The club day at `now`.
  def today(now = Time.current) = now.in_time_zone(TIME_ZONE).to_date

  # Whether a stored day-precision timestamp (a date saved as UTC midnight,
  # or a full timestamp) lands after today. Its UTC day must be after the
  # club day and the moment itself still to come, so a timestamp of "now" on
  # a club evening, already the next UTC day, is not in the future.
  def after_today?(time, now = Time.current) = time.utc.to_date > today(now) && time > now
end
