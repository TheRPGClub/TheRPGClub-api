# frozen_string_literal: true

# Achievement Hub catch-up on boot (ADR 0003): Achievements::BootCatchUpJob
# restarts the Provider ticks a deploy interrupted, after one PSN login
# attempt while the PSN pause is on. It runs as a job, so boot never waits on
# Sony or fails on it. Server processes only (never console, rake or specs).
Rails.application.config.after_initialize do
  Achievements::BootCatchUpJob.perform_later if defined?(Rails::Server)
end
