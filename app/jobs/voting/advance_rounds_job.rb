# frozen_string_literal: true

module Voting
  # Scheduled every minute in config/recurring.yml, but only sweeps when
  # Voting::SweepSchedule says the round has something due, so the quiet
  # minutes in between never wake Neon. Skipped while Voting & GOTM is Off;
  # the first sweep after it is back on catches up on what fell due.
  # VOTING_AUTOMATION_ENABLED stays a separate deployment switch.
  class AdvanceRoundsJob < ApplicationJob
    queue_as :default

    def perform
      return unless Voting.automation_enabled?
      return if Features.off?("voting_gotm")

      now = Time.current
      return unless SweepSchedule.due?(now)

      Voting::AdvanceRounds.call(now: now)
      SweepSchedule.record(Voting::AdvanceRounds.next_event_at(now: now), now)
    end
  end
end
