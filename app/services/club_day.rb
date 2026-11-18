# frozen_string_literal: true

# The club day (GLOSSARY.md, "club day"): a calendar day in the club's time
# zone, America/New_York, the one voting is scheduled in. Challenges,
# Birth Dates and Birthdays all count days this way.
module ClubDay
  TIME_ZONE = Voting::Schedule::TIME_ZONE

  module_function

  # The club day at `now`.
  def today(now = Time.current) = now.in_time_zone(TIME_ZONE).to_date
end
