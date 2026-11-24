# frozen_string_literal: true

# The club day (GLOSSARY.md, "club day"): a calendar day in the club's time
# zone, America/New_York, the one voting is scheduled in. Challenges,
# Birth Dates and Birthdays all count days this way.
module ClubDay
  TIME_ZONE = Voting::Schedule::TIME_ZONE
  DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

  module_function

  # The club day at `now`.
  def today(now = Time.current) = now.in_time_zone(TIME_ZONE).to_date

  # The club day a stored timestamp falls on: the one rule every reader of a
  # day-precision moment uses (Game Completion `completed_at`, Now Playing
  # `added_at`). Day writes are stored at noon club time (`noon`), which has
  # the same UTC date, so the UTC-date export agrees with it.
  def day_of(time) = time && today(time)

  # Noon club time on `date`: how a day is stored in a timestamp column.
  def noon(date) = Time.find_zone!(TIME_ZONE).local(date.year, date.month, date.day, 12)

  # The club day a day-precision write names, or nil when `value` is blank or
  # unreadable. A `Date` or a date-only `YYYY-MM-DD` string is that date; a
  # full timestamp (a `Time` or an ISO 8601 string) is the club day it falls
  # on, so the bot's "now" on a club evening is today, not tomorrow.
  def day_named(value)
    case value
    when Time, DateTime, ActiveSupport::TimeWithZone then today(value)
    when Date then value
    when String then day_named_in(value.strip)
    end
  end

  def day_named_in(text)
    return nil if text.empty?
    return Date.iso8601(text) if DATE_ONLY.match?(text)

    moment = Time.zone.parse(text)
    moment && today(moment)
  rescue ArgumentError
    nil
  end
  private_class_method :day_named_in
end
