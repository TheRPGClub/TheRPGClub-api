# frozen_string_literal: true

namespace :franchise_progress do
  desc "Launch backfill: write the Conquests members already hold, unannounced (safe to run again)"
  task backfill_conquests: :environment do
    check = Franchises::ConquestCheck.new(announce: false)
    franchise_ids = GamedbGameFranchise.where(mainline: true).distinct.select(:franchise_id)
    written = GamedbFranchise.current.where(franchise_id: franchise_ids).find_each.sum do |franchise|
      check.for_franchise(franchise).size
    end
    puts "Backfilled Conquests: #{written} written."
  end
end
