# frozen_string_literal: true

module Birthdays
  # Upcoming Birthdays (spec #396, api#400): the shared Birthdays falling
  # from a club day through the next DAYS - 1 days, of members still in the
  # server, on the date each falls on (Birthdays.falls_on: a 29 February
  # Birthday falls on 28 February in other years).
  # Members are looked up by month and day directly (ADR 0011). Each entry is
  # the member, the month and day, the date it falls on and whether that is
  # today; never the year or the age. `next_beyond` gives the first one after
  # the window, without the member.
  module Upcoming
    DAYS = 30

    module_function

    # `today` is the club day (ClubDay.today). Ordered by the date the
    # Birthday falls on, then by the member's name (Members.by_name, as the
    # Birthday Post orders them).
    def entries(today)
      falls_on = window(today)

      RpgClubUser.active.without_images.where(birthday_shared: true)
        .where([ :birth_month, :birth_day ] => falls_on.keys)
        .map { |user| [ user, falls_on.fetch([ user.birth_month, user.birth_day ]) ] }
        .sort_by { |user, on| [ on, *Members.by_name(user) ] }
        .map { |user, on| entry(user, on, today) }
    end

    # The first shared Birthday after the window (owner decision 11, for the
    # bot's empty /birthdays): its month, day and the date it falls on, never
    # whose it is. A Birthday in the window counts with its date next year.
    # nil when no member still in the server shares one.
    def next_beyond(today)
      last = today + DAYS - 1

      RpgClubUser.active.where(birthday_shared: true).distinct.pluck(:birth_month, :birth_day)
        .map { |month, day| [ next_after(month, day, last), month, day ] }
        .min
        &.then { |on, month, day| { month: month, day: day, on: on.iso8601 } }
    end

    # The first date after `last` a Birthday of `month` and `day` falls on.
    def next_after(month, day, last)
      [ last.year, last.year + 1 ].map { |year| Birthdays.falls_on(month, day, year) }.find { |on| on > last }
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
