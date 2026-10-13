# frozen_string_literal: true

module Voting
  # When the round-lifecycle sweep (Voting::AdvanceRoundsJob) next has work,
  # so its every-minute schedule can skip without touching Neon. Querying the
  # current round every minute would reset Neon's 5-minute autosuspend timer
  # forever and keep the compute awake 24/7.
  #
  # Kept in a file store on the machine's local disk, not Rails.cache (Solid
  # Cache lives on Neon) or process memory: Solid Queue's worker is a process
  # forked from Puma, and the web requests that change a round must be able
  # to clear it. A fresh machine (every deploy) starts empty, so its first
  # sweep runs. Changes this machine's processes do not see (SQL run by hand,
  # a `fly console` machine), or one committed during a sweep and overwritten
  # by its #record, are picked up within RECHECK.
  module SweepSchedule
    KEY = "next_sweep_at"
    RECHECK = 6.hours

    module_function

    # Whether the sweep should run at `now`: when it is unknown when the
    # sweep next has work, or that moment has come.
    def due?(now = Time.current)
      next_sweep_at = store.read(KEY)
      next_sweep_at.nil? || now >= next_sweep_at
    end

    # Records the sweep's next event (Voting::AdvanceRounds.next_event_at),
    # nil when none is scheduled. Runs again by RECHECK at the latest.
    def record(next_event_at, now = Time.current)
      store.write(KEY, [ next_event_at, now + RECHECK ].compact.min)
    end

    # Called whenever a round or its events change, so the next minute's
    # sweep looks again.
    def clear
      store.delete(KEY)
    end

    def store
      @store ||= ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "voting_sweep", Rails.env))
    end
  end
end
