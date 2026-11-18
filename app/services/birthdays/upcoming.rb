# frozen_string_literal: true

module Birthdays
  # Upcoming Birthdays (spec #396, api#400): the shared Birthdays falling
  # from a club day through the next DAYS - 1 days, of members still in the
  # server, on the date each falls on (Birthdays.falls_on: a 29 February
  # Birthday falls on 28 February in other years).
  # Members are looked up by month and day directly (ADR 0011). Each entry is
  # the member, the month and day, the date it falls on and whether that is
  # today; never the year or the age.
  module Upcoming
    DAYS = 30

    module_function

    # `today` is the club day (ClubDay.today). Ordered by the date the
    # Birthday falls on, then by the member's display name.
    def entries(today)
      falls_on = window(today)

      RpgClubUser.active.without_images.where(birthday_shared: true)
        .where([ :birth_month, :birth_day ] => falls_on.keys)
        .map { |user| entry(user, falls_on.fetch([ user.birth_month, user.birth_day ]), today) }
        .sort_by { |entry| [ entry[:on], entry[:display_name].downcase, entry[:user_id] ] }
    end

    # [month, day] => the date in the window a Birthday on it falls on
    # (Birthdays.days_falling_on).
    def window(today)
      (today...(today + DAYS)).each_with_object({}) do |date, falls_on|
        Birthdays.days_falling_on(date).each { |month_day| falls_on[month_day] = date }
      end
    end

    def entry(user, on, today)
      Members.summary(user).merge(
        display_name: Members.display_name(user),
        month: user.birth_month, day: user.birth_day,
        on: on.iso8601, today: on == today
      )
    end
  end
end
