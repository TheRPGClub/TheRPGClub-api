# frozen_string_literal: true

namespace :franchise_progress do
  desc "Launch backfill: write the Conquests members already hold, unannounced (safe to run again). " \
       "The deploy runs it once through a data migration."
  task backfill_conquests: :environment do
    puts "Backfilled Conquests: #{Franchises::ConquestBackfill.call} written."
  end
end
