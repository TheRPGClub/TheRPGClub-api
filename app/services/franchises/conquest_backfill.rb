# frozen_string_literal: true

module Franchises
  # Launch backfill (spec api#457): writes the Conquests members already hold,
  # unannounced, so the first live Conquest check doesn't post them as new.
  # Safe to run again: existing Conquests are left as they are.
  #
  #   Franchises::ConquestBackfill.call # => 12 (Conquests written)
  module ConquestBackfill
    def self.call
      check = ConquestCheck.new(announce: false)
      franchise_ids = GamedbGameFranchise.where(mainline: true).distinct.select(:franchise_id)
      GamedbFranchise.current.where(franchise_id: franchise_ids).find_each.sum do |franchise|
        check.for_franchise(franchise).size
      end
    end
  end
end
