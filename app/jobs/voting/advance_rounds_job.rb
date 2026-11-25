# frozen_string_literal: true

module Voting
  # Scheduled every minute in config/recurring.yml, but only sweeps when
  # Voting::SweepSchedule says the GOTM round or the GOTY Vote has something
  # due, so the quiet minutes in between never wake Neon. The Feature Flags
  # are read only when a sweep is due, for the same reason. A Feature that is
  # Off (Voting & GOTM for the round, GOTY Vote for the GOTY Vote) has its
  # half skipped; with both Off the sweep is looked at again by
  # SweepSchedule::RECHECK, and setting either flag (Features::ChangeFlag)
  # clears the schedule, so the first minute after it is back on catches up
  # on what fell due. VOTING_AUTOMATION_ENABLED stays a separate deployment
  # switch.
  class AdvanceRoundsJob < ApplicationJob
    queue_as :default

    def perform
      return unless Voting.automation_enabled?

      now = Time.current
      return unless SweepSchedule.due?(now)

      rounds = !Features.off?("voting_gotm")
      goty = !Features.off?("goty_vote")
      Voting::AdvanceRounds.call(now: now) if rounds
      Goty::AdvanceVotes.call(now: now) if goty
      next_at = [
        (Voting::AdvanceRounds.next_event_at(now: now) if rounds),
        (Goty::AdvanceVotes.next_event_at(now: now) if goty)
      ].compact.min
      SweepSchedule.record(next_at, now)
    end
  end
end
