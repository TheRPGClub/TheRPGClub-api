# frozen_string_literal: true

module Goty
  # The GOTY Vote's default calendar, in US Eastern like Voting::Schedule:
  # year Y's nominations open January 1 of Y+1 at midnight, and its vote opens
  # at noon on the first Friday on or after January 15, running through the
  # end of that weekend's Sunday.
  module Schedule
    VOTING_FROM_DAY = 15

    module_function

    def nominations_open_at(year)
      Date.new(year + 1, 1, 1).in_time_zone(Voting::Schedule::TIME_ZONE)
    end

    def voting_opens_at(year)
      day = Date.new(year + 1, 1, VOTING_FROM_DAY)
      day += 1 until day.wday == Voting::Schedule::FRIDAY
      day.in_time_zone(Voting::Schedule::TIME_ZONE).change(hour: Voting::Schedule::VOTE_HOUR)
    end

    def voting_closes_at(opens_at)
      Voting::Schedule.default_closes_at(opens_at)
    end
  end
end
