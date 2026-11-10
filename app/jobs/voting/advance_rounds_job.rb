# frozen_string_literal: true

module Voting
  # Scheduled every minute in config/recurring.yml, but only sweeps when
  # Voting::SweepSchedule says the round has something due, so the quiet
  # minutes in between never wake Neon. The Feature Flag is read only when a
  # sweep is due, for the same reason. While Voting & GOTM is Off the sweep is
  # skipped and looked at again by SweepSchedule::RECHECK; setting the flag
  # (Features::ChangeFlag) clears the schedule, so the first minute after it
  # is back on catches up on what fell due. VOTING_AUTOMATION_ENABLED stays a
  # separate deployment switch.
  class AdvanceRoundsJob < ApplicationJob
    queue_as :default

    def perform
      return unless Voting.automation_enabled?

      now = Time.current
      return unless SweepSchedule.due?(now)
      return SweepSchedule.record(nil, now) if Features.off?("voting_gotm")

      Voting::AdvanceRounds.call(now: now)
      SweepSchedule.record(Voting::AdvanceRounds.next_event_at(now: now), now)
    end
  end
end
