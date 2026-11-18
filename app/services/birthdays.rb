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

  # The members of `users` whose Birthday falls on `date`, shared or not (by
  # month and day, ADR 0011): those born on its month and day, and on
  # 28 February of a non-leap year those born on 29 February too.
  def self.falling_on(date, users = RpgClubUser.all)
    born = users.where(birth_month: date.month, birth_day: date.day)
    return born unless date.month == 2 && date.day == 28 && !date.leap?

    born.or(users.where(birth_month: 2, birth_day: 29))
  end
end
