# frozen_string_literal: true

namespace :db do
  namespace :queue do
    desc "Create the Solid Queue schema in the queue database if it is missing"
    # db:prepare cannot do this for us: the app runs schema_format = :sql
    # (config/application.rb), so prepare looks for db/queue_structure.sql,
    # and when a schema file is missing it *silently* skips the load -- which
    # is how the queue database kept coming up empty and crash-looping the
    # in-puma Solid Queue supervisor (#205, #206). Solid Queue ships its
    # schema as Ruby (db/queue_schema.rb), so load it explicitly instead.
    task bootstrap: :environment do
      config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "queue")
      abort "No queue database configured for #{Rails.env}" unless config

      ActiveRecord::Base.establish_connection(config)
      if ActiveRecord::Base.connection.table_exists?("solid_queue_jobs")
        puts "db:queue:bootstrap: queue database already has its schema"
      else
        load Rails.root.join("db/queue_schema.rb")
        puts "db:queue:bootstrap: loaded db/queue_schema.rb into #{config.database}"
      end
    end
  end
end
