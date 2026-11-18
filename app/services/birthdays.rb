# frozen_string_literal: true

# Birthdays (GLOSSARY.md, "Birthday"; spec #396): the day and month of a
# member's Birth Date, celebrated only when the member shares it. A utility,
# not a Feature: no Feature Flag gates anything here.
#
# The one rule for which day a Birthday falls on lives here, for the Birthday
# Post (Birthdays::PostJob) and Upcoming Birthdays alike: on its month and day,
# except that a 29 February Birthday falls on 28 February in non-leap years
# (ADR 0011).
module Birthdays
  # Club days are America/New_York days, as for Challenges and voting.
  TIME_ZONE = Voting::Schedule::TIME_ZONE

  # The club's date at `now`.
  def self.today(now = Time.current) = now.in_time_zone(TIME_ZONE).to_date

  # The date a Birthday of `month` and `day` falls on in `year`.
  def self.falls_on(month, day, year)
    return Date.new(year, 2, 28) if month == 2 && day == 29 && !Date.leap?(year)

    Date.new(year, month, day)
  end

  # The [month, day] Birthdays falling on `date` (by falls_on): its own month
  # and day, and on 28 February of a non-leap year 29 February too.
  def self.days_falling_on(date)
    [ [ date.month, date.day ], [ 2, 29 ] ].uniq.select { |month, day| falls_on(month, day, date.year) == date }
  end

  # The members of `users` whose Birthday falls on `date`, shared or not (by
  # month and day, ADR 0011).
  def self.falling_on(date, users = RpgClubUser.all)
    users.where([ :birth_month, :birth_day ] => days_falling_on(date))
  end
end
