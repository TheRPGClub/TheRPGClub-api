# frozen_string_literal: true

require "sqlite3"

class NewsItem
  # The News Feed Stamp: a number that changes whenever a News Item is
  # recorded, changed or removed, so an open News page can ask "anything
  # new?" every few seconds and reload the feed only when the answer is yes.
  # Kept in a machine-local SQLite file for the same reason as
  # BotJob::WorkSignal: a steady poll against Neon would keep the compute
  # awake around the clock, so reading the stamp never touches Postgres.
  #
  # One row holding `stamp` (unix milliseconds of the last change, bumped by
  # at least one). A missing file starts at the current time, so after a
  # fresh machine (ephemeral rootfs) every open page reloads once.
  #
  # Assumes a single API machine, as today. Several machines would need a
  # shared stamp.
  module FeedStamp
    module_function

    # Mark the feed changed.
    def bump!(now: Time.current)
      with_db do |db|
        db.execute("UPDATE stamp SET value = MAX(value + 1, ?) WHERE id = 1", [ (now.to_f * 1000).to_i ])
      end
    end

    # The current stamp, an Integer.
    def read
      with_db { |db| db.get_first_value("SELECT value FROM stamp WHERE id = 1") }
    end

    def path
      Rails.root.join("storage", "#{Rails.env}_news_feed_stamp.sqlite3").to_s
    end

    # Creates the file, table and row if missing. Run once at boot by
    # config/initializers/news_feed_stamp.rb; with_db runs it again only when
    # the table has gone (the file was deleted).
    def setup!
      FileUtils.mkdir_p(File.dirname(path))
      db = SQLite3::Database.new(path)
      db.busy_timeout = 5000
      create_schema(db)
    ensure
      db&.close
    end

    def create_schema(db)
      db.execute("CREATE TABLE IF NOT EXISTS stamp (id INTEGER PRIMARY KEY, value INTEGER NOT NULL)")
      db.execute("INSERT OR IGNORE INTO stamp (id, value) VALUES (1, ?)", [ (Time.current.to_f * 1000).to_i ])
    end

    def with_db
      retried = false
      begin
        db = SQLite3::Database.new(path)
        db.busy_timeout = 5000
        yield db
      rescue SQLite3::SQLException, SQLite3::CantOpenException => error
        raise if retried || error.is_a?(SQLite3::SQLException) && !error.message.include?("no such table")

        db&.close
        db = nil
        retried = true
        setup!
        retry
      ensure
        db&.close
      end
    end
  end
end
