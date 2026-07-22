# frozen_string_literal: true

# db:prepare cannot load the Solid Cache / Solid Queue schemas for us: the app
# runs schema_format = :sql (config/application.rb), so prepare looks for
# db/<name>_structure.sql, and when a schema file is missing it *silently*
# skips the load — which is how the Neon cache/queue databases sat empty until
# 2026-07-22 and how the SQLite queue kept crash-looping the in-puma Solid
# Queue supervisor (#205, #206). The solid gems ship their schemas as Ruby
# (db/cache_schema.rb, db/queue_schema.rb), so load them explicitly instead.
def bootstrap_solid_schema(config_name:, sentinel_table:, schema_file:)
  config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: config_name)
  abort "No #{config_name} database configured for #{Rails.env}" unless config

  ActiveRecord::Base.establish_connection(config)
  if ActiveRecord::Base.connection.table_exists?(sentinel_table)
    puts "db:#{config_name}:bootstrap: #{config_name} database already has its schema"
  else
    load Rails.root.join(schema_file)
    puts "db:#{config_name}:bootstrap: loaded #{schema_file} into #{config.database}"
  end
end

namespace :db do
  namespace :queue do
    desc "Create the Solid Queue schema in the queue database if it is missing"
    # Run by bin/docker-entrypoint on every machine boot: the SQLite queue
    # database lives on the ephemeral rootfs and must be recreated each time.
    task bootstrap: :environment do
      bootstrap_solid_schema(config_name: "queue", sentinel_table: "solid_queue_jobs", schema_file: "db/queue_schema.rb")
    end
  end

  namespace :cache do
    desc "Create the Solid Cache schema in the cache database if it is missing"
    # Run by the fly.toml release_command after db:prepare: a freshly
    # provisioned cache database would otherwise come up empty (the silent
    # skip above) and 500 every cached endpoint, as production did on
    # 2026-07-22 until the schema was hand-loaded.
    task bootstrap: :environment do
      bootstrap_solid_schema(config_name: "cache", sentinel_table: "solid_cache_entries", schema_file: "db/cache_schema.rb")
    end
  end
end
