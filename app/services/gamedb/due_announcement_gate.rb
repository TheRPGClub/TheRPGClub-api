# frozen_string_literal: true

module Gamedb
  # When the release-announcement due feed (GET /release_announcements/due)
  # next has something to offer, so the bot's hourly poll can be answered
  # without touching Neon. Querying every hour would wake Neon's compute
  # every hour for nothing most of the time.
  #
  # Kept in a file store on the machine's local disk, like
  # Voting::SweepSchedule, not Rails.cache (Solid Cache lives on Neon) or
  # process memory (Solid Queue's worker is a forked process, and an IGDB
  # refresh there must be able to clear it). A fresh machine (every deploy)
  # starts empty, so its first poll queries. Every announcement write clears
  # it after commit (GamedbReleaseAnnouncement, ReleaseAnnouncementSchedule);
  # anything else (SQL run by hand) is picked up within RECHECK.
  module DueAnnouncementGate
    KEY = "next_due_at"
    RECHECK = 6.hours

    module_function

    # Whether the due feed must query at `now`: unknown, or the next
    # announcement's time has come.
    def due?(now = Time.current)
      next_due_at = store.read(KEY)
      next_due_at.nil? || now >= next_due_at
    end

    # Records when the next pending announcement comes due (nil when none is
    # scheduled), RECHECK from now at the latest.
    def record(next_due_at, now = Time.current)
      store.write(KEY, [ next_due_at, now + RECHECK ].compact.min)
    end

    def clear
      store.delete(KEY)
    end

    # Clears once the current transaction commits (at once outside one), so a
    # poll racing the write can't record a time from before it.
    def clear_after_commit
      ActiveRecord.after_all_transactions_commit { clear }
    end

    def store
      @store ||= ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp", "cache", "due_announcements", Rails.env))
    end
  end
end
