# frozen_string_literal: true

module Voting
  # Scheduled every minute in config/recurring.yml, but only sweeps when
  # Voting::SweepSchedule says the round has something due, so the quiet
  # minutes in between never wake Neon.
  class AdvanceRoundsJob < ApplicationJob
    queue_as :default

    def perform
      return unless Voting.automation_enabled?

      now = Time.current
      return unless SweepSchedule.due?(now)

      Voting::AdvanceRounds.call(now: now)
      SweepSchedule.record(Voting::AdvanceRounds.next_event_at(now: now), now)
    end
  end
end
