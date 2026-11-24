# frozen_string_literal: true

# Game Lists feeding Pool Challenges (spec api#442, ticket api#448).
#
#   challenges.pool_game_list_id   the Game List the Pool was started from,
#                                  a live source of Optional Games; null
#                                  when none (or the link ended). Set only
#                                  on create (Challenges::ListLink).
#   challenge_pool_list_notices    "<game> was removed from <list>": a Core
#                                  Game whose entry left the linked list,
#                                  open until the Host removes it from the
#                                  Challenge or keeps it. One per game per
#                                  Challenge.
#
# The link is nullified with its list, though the API ends it itself first
# (keeping the list's Optional Games as picked by hand).
class LinkGameListsToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :challenges, :pool_game_list_id, :bigint
    add_index :challenges, :pool_game_list_id, name: "ix_challenges_pool_game_list", where: "pool_game_list_id IS NOT NULL"
    add_foreign_key :challenges, :game_lists, column: :pool_game_list_id, on_delete: :nullify,
      name: "fk_challenges_pool_game_list"

    create_table :challenge_pool_list_notices do |t|
      t.bigint :challenge_id, null: false
      t.bigint :game_id, null: false
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.index %i[challenge_id game_id], unique: true, name: "ux_challenge_pool_list_notices"
      t.index :game_id, name: "ix_challenge_pool_list_notices_game"
    end
    add_foreign_key :challenge_pool_list_notices, :challenges, on_delete: :cascade,
      name: "fk_challenge_pool_list_notices_challenge"
    add_foreign_key :challenge_pool_list_notices, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade, name: "fk_challenge_pool_list_notices_game"
  end
end
