# frozen_string_literal: true

require "sqlite3"

class BotJob
  # The "work waiting" signal, kept in a machine-local SQLite file so the
  # bot's ~10s poll can answer "nothing" without touching Postgres: Neon
  # autosuspends after 5 idle minutes, and a steady poll against it (or
  # against Solid Cache, which also lives on Neon) would keep the compute
  # awake around the clock. Same reasoning as the Solid Queue database in
  # config/database.yml.
  #
  # One row: `due_at` (unix seconds, NULL = never) and a `version` bumped by
  # every set!. The signal is up while due_at <= now. A missing file or row
  # reads as up, so a fresh machine (ephemeral rootfs) checks Postgres once;
  # config/initializers/bot_job_work_signal.rb also raises it on server boot.
  #
  # Assumes a single API machine, as today. Several machines would need a
  # shared signal.
  module WorkSignal
    module_function

    # Raise the signal (a job was created).
    def set!
      with_db do |db|
        db.execute("UPDATE signal SET due_at = 0, version = version + 1 WHERE id = 1")
      end
    end

    # The current state: `{ up:, version: }`.
    def read(now: Time.current)
      with_db do |db|
        due_at, version = db.get_first_row("SELECT due_at, version FROM signal WHERE id = 1")
        { up: !due_at.nil? && due_at <= now.to_f, version: version }
      end
    end

    # Lower the signal unless it was raised since `version` was read. With
    # `wake_at` it comes back up by itself then (a claim lease running out).
    def clear!(version:, wake_at: nil)
      with_db do |db|
        db.execute("UPDATE signal SET due_at = ? WHERE id = 1 AND version = ?", [ wake_at&.to_f, version ])
      end
    end

    def path
      Rails.root.join("storage", "#{Rails.env}_bot_job_signal.sqlite3").to_s
    end

    def with_db
      FileUtils.mkdir_p(File.dirname(path))
      db = SQLite3::Database.new(path)
      db.busy_timeout = 5000
      db.execute("CREATE TABLE IF NOT EXISTS signal (id INTEGER PRIMARY KEY, due_at REAL, version INTEGER NOT NULL)")
      db.execute("INSERT OR IGNORE INTO signal (id, due_at, version) VALUES (1, 0, 0)")
      yield db
    ensure
      db&.close
    end
  end
end
