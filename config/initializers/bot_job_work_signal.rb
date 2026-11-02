# frozen_string_literal: true

# Create the bot job signal's SQLite file once per process, so its reads and
# writes skip the schema setup (see BotJob::WorkSignal). Then raise the signal
# on server boot so a restarted process checks Postgres once for jobs queued
# before it started. Server processes only, like the Achievement Hub catch-up.
Rails.application.config.after_initialize do
  BotJob::WorkSignal.setup!
  BotJob::WorkSignal.set! if defined?(Rails::Server)
end
