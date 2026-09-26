# frozen_string_literal: true

module Voting
  # The club's calendar rules, in US Eastern: a vote opens on the last Friday
  # of the month at noon and runs through the end of that weekend's Sunday;
  # nomination reminders go out at 17:00 five days and one day before it
  # opens. Ported from the bot's VoteDateUtils / NominationReminderService so
  # the backend is the one place they live.
  module Schedule
    TIME_ZONE = "America/New_York"
    VOTE_HOUR = 12
    REMINDER_HOUR = 17
    FRIDAY = 5

    module_function

    # The end of the first Sunday at/after the open.
    def default_closes_at(opens_at)
      opens = opens_at.in_time_zone(TIME_ZONE)
      days_until_sunday = (7 - opens.wday) % 7 # wday: Sunday == 0
      (opens + days_until_sunday.days).end_of_day
    end

    # When the round after one that opened at `previous_opens_at` opens: the
    # last Friday of the following month. Anchored to the previous round rather
    # than to now, so a round decided late (a tie resolved days after the
    # close) still schedules the next month, not the one after.
    def next_opens_at(previous_opens_at)
      day = previous_opens_at.in_time_zone(TIME_ZONE).next_month.end_of_month.to_date
      day -= 1 until day.wday == FRIDAY
      day.in_time_zone(TIME_ZONE).change(hour: VOTE_HOUR)
    end

    # The month the round's winners are played in: the one after the vote.
    def month_label(opens_at)
      opens_at.in_time_zone(TIME_ZONE).next_month.strftime("%B %Y")
    end

    def reminder_at(opens_at, days_before)
      day = opens_at.in_time_zone(TIME_ZONE).to_date - days_before
      day.in_time_zone(TIME_ZONE).change(hour: REMINDER_HOUR)
    end
  end
end
