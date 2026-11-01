# frozen_string_literal: true

# Achievement Hub catch-up on boot (ADR 0003). The queue database is recreated
# on every deploy, so a Sync Window or Backfill that a deploy interrupted has
# lost its tick chains; its durable state in Postgres has not. Enqueueing the
# three Provider ticks once resumes it: each tick does a single query and stops
# when nothing is due. Server processes only (never console, rake or specs).
Rails.application.config.after_initialize do
  Achievements::ProviderTickJob.enqueue_all if defined?(Rails::Server)
end
