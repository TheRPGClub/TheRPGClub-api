# frozen_string_literal: true

# Raise the bot job signal on server boot so a restarted process checks
# Postgres once for jobs queued before it started (see BotJob::WorkSignal).
# Server processes only, like the Achievement Hub catch-up.
Rails.application.config.after_initialize do
  BotJob::WorkSignal.set! if defined?(Rails::Server)
end
