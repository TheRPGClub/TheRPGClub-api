# frozen_string_literal: true

# Counts past play (spec #376, ticket #382): the Host of an Always Open Slots
# Challenge lets earlier play count. Members then pick Game Completions dated
# before their Run started for open slots (`challenge_run_entries.picked_by_hand`,
# from #381); earlier play never fills a slot by itself.
class AddCountsPastPlayToChallenges < ActiveRecord::Migration[8.1]
  def change
    change_table :challenges, bulk: true do |t|
      t.boolean :counts_past_play, null: false, default: false
      t.check_constraint "NOT counts_past_play OR schedule = 'always_open'", name: "ck_challenges_past_play_always_open"
    end
  end
end
