# frozen_string_literal: true

module Challenges
  # The Challenges lifecycle (Challenges::Lifecycle), scheduled every minute
  # in config/recurring.yml like Voting::AdvanceRoundsJob, and like it only
  # sweeping when Challenges::SweepSchedule says a step is due, so the quiet
  # minutes never wake Neon. The Feature Flag is read only when a sweep is
  # due. While Challenges is Off its automated activity is paused: the sweep
  # is skipped and looked at again by SweepSchedule::RECHECK, and setting the
  # flag clears the schedule, so the next minute catches up on what fell due.
  class LifecycleJob < ApplicationJob
    queue_as :default

    def perform
      now = Time.current
      return unless SweepSchedule.due?(now)
      return SweepSchedule.record(nil, now) if Features.off?(Announcements::FEATURE_KEY)

      Lifecycle.call(now: now)
      SweepSchedule.record(Lifecycle.next_event_at(now: now), now)
    end
  end
end
