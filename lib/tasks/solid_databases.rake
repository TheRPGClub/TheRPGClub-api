# frozen_string_literal: true

# The production queue database is a machine-local SQLite file. The Fly release
# machine prepares a different ephemeral filesystem, so each app machine must
# load db/queue_schema.rb for itself when it starts.
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
end
