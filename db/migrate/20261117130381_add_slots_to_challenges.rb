# frozen_string_literal: true

# Challenges (GLOSSARY.md, "Slots"; spec #376, ticket #381): the Slots
# Challenge Format, one slot per release year in a range.
#
# A Slots Challenge's range runs from `slots_first_year` (null: each member's
# birth year) to `slots_last_year` (null: the current year, so the range
# gains a slot every 1 January). A Run copies its first year when it starts
# (`challenge_runs.first_year`) and keeps it, even if the member's Birth Date
# changes later. Caught Up is worked out, never stored; a Run only remembers
# the year it was last announced as Caught Up, so it is announced once a year.
#
# Each Cleared game on a Slots Run fills at most one slot (`slot_year`);
# `picked_by_hand` marks a game the member moved to its slot (ticket #382 uses
# it for past-play picks too).
class AddSlotsToChallenges < ActiveRecord::Migration[8.1]
  def change
    change_table :challenges, bulk: true do |t|
      t.integer :slots_first_year, limit: 2
      t.integer :slots_last_year, limit: 2
      t.check_constraint "slots_first_year IS NULL OR slots_last_year IS NULL OR slots_first_year <= slots_last_year",
        name: "ck_challenges_slots_range"
    end

    change_table :challenge_runs, bulk: true do |t|
      t.integer :first_year, limit: 2
      t.integer :caught_up_announced_year, limit: 2
    end

    change_table :challenge_run_entries, bulk: true do |t|
      t.integer :slot_year, limit: 2
      t.boolean :picked_by_hand, null: false, default: false
      t.check_constraint "slot_year IS NULL OR state = 'cleared'", name: "ck_challenge_run_entries_slot_cleared"
    end
  end
end
