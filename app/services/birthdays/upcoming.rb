# frozen_string_literal: true

module Birthdays
  # Upcoming Birthdays (spec #396, api#400): the shared Birthdays falling
  # from a club day through the next DAYS - 1 days, of members still in the
  # server. A 29 February Birthday falls on 28 February in other years.
  # Members are looked up by month and day directly (ADR 0011). Each entry is
  # the member, the month and day, the date it falls on and whether that is
  # today; never the year or the age.
  module Upcoming
    DAYS = 30

    module_function

    # `today` is the club's date (Challenges.today). Ordered by the date the
    # Birthday falls on, then by the member's display name.
    def entries(today)
      falls_on = window(today)

      RpgClubUser.active.without_images.where(birthday_shared: true)
        .where([ :birth_month, :birth_day ] => falls_on.keys)
        .map { |user| entry(user, falls_on.fetch([ user.birth_month, user.birth_day ]), today) }
        .sort_by { |entry| [ entry[:on], entry[:display_name].downcase, entry[:user_id] ] }
    end

    # [month, day] => the date in the window a Birthday on it falls on.
    def window(today)
      days = (today...(today + DAYS))
      days.each_with_object({}) do |date, falls_on|
        falls_on[[ date.month, date.day ]] = date
        falls_on[[ 2, 29 ]] = date if date.month == 2 && date.day == 28 && !date.leap?
      end
    end

    def entry(user, on, today)
      Challenges.member(user).merge(
        display_name: Challenges.display_name(user),
        month: user.birth_month, day: user.birth_day,
        on: on.iso8601, today: on == today
      )
    end
  end
end
