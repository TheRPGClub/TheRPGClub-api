# frozen_string_literal: true

# Secret Santa: picks, reveal and the year to Clear (GLOSSARY.md,
# "Assignment", "Edition"; spec #376, ticket #384).
#
# A drawn member (a Santa) picks one game from their recipient's backlog
# before the pick deadline. The pick lives on the Santa's sign-up row:
# `picked_game_id`, when it was picked, and whether it was the Santa's own
# pick or a random one at the deadline (`picked_randomly`). A Santa who
# withdraws after the draw keeps their row with `withdrawn_at` (the circle is
# never redrawn) and their recipient gets a random pick.
#
# `challenge_editions.picks_closed_at` records that the random picks were
# made at the deadline, so they are made once.
class AddPicksToChallengeEditions < ActiveRecord::Migration[8.1]
  def change
    change_table :challenge_edition_signups, bulk: true do |t|
      t.bigint :picked_game_id
      t.timestamptz :picked_at
      t.boolean :picked_randomly, null: false, default: false
      t.timestamptz :withdrawn_at
    end
    add_foreign_key :challenge_edition_signups, :gamedb_games, column: :picked_game_id, primary_key: :game_id,
      on_delete: :nullify, name: "fk_challenge_edition_signups_picked_game"

    add_column :challenge_editions, :picks_closed_at, :timestamptz
  end
end
