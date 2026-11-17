# frozen_string_literal: true

module Challenges
  # When the Challenges lifecycle job (Challenges::LifecycleJob) next has
  # work, so its every-minute schedule can skip without touching Neon. The
  # same idea as Voting::SweepSchedule, and kept the same way: a file store on
  # the machine's local disk that the web requests changing a Challenge can
  # clear (Challenge's after_commit, and Features::ChangeFlag for the
  # `challenges` Feature). A fresh machine starts empty, so its first sweep
  # runs; anything this machine's processes do not see is picked up within
  # RECHECK.
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

    # Records the sweep's next event (Challenges::Lifecycle.next_event_at),
    # nil when none is scheduled. Runs again by RECHECK at the latest.
    def record(next_event_at, now = Time.current)
      store.write(KEY, [ next_event_at, now + RECHECK ].compact.min)
    end

    # Called whenever a Challenge changes, so the next minute's sweep looks
    # again.
    def clear
      store.delete(KEY)
    end

    def store
      @store ||= ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "challenges_sweep", Rails.env))
    end
  end
end
