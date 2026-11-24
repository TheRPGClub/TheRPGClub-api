# frozen_string_literal: true

# Core and Optional Games in Pools (spec api#442, ticket api#445; ADR 0014).
#
# - A game a person put in a Pool is `core` or `optional`, or `exclude`d
#   from its sources, and remembers when it joined (`added_at`), so a new
#   Optional Game can be marked "new".
# - `pool_target` ("N Cleared games", null for "all") becomes
#   `pool_optional_target`: how many Optional Games a Run must Clear besides
#   every Core Game, 0 by default.
#
# Production has no Pool Challenges. A development Pool keeps its meaning as
# well as it can: a game included by hand becomes Optional, and the target
# becomes the Optional target ("all" becomes 0). Existing rows joined when
# their Challenge was created, so none of them shows as new.
class ReworkChallengePools < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :challenge_pool_games, name: "ck_challenge_pool_games_inclusion"
    execute "UPDATE challenge_pool_games SET inclusion = 'optional' WHERE inclusion = 'include'"
    add_check_constraint :challenge_pool_games, "inclusion IN ('core', 'optional', 'exclude')",
      name: "ck_challenge_pool_games_inclusion"
    add_column :challenge_pool_games, :added_at, :datetime
    execute <<~SQL.squish
      UPDATE challenge_pool_games SET added_at = challenges.created_at
        FROM challenges WHERE challenges.id = challenge_pool_games.challenge_id
    SQL
    change_column_null :challenge_pool_games, :added_at, false
    change_column_default :challenge_pool_games, :added_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }

    add_column :challenges, :pool_optional_target, :integer, null: false, default: 0
    execute "UPDATE challenges SET pool_optional_target = COALESCE(pool_target, 0)"
    remove_column :challenges, :pool_target
    add_check_constraint :challenges, "pool_optional_target >= 0", name: "ck_challenges_pool_optional_target"
  end

  def down
    remove_check_constraint :challenges, name: "ck_challenges_pool_optional_target"
    add_column :challenges, :pool_target, :integer
    execute "UPDATE challenges SET pool_target = NULLIF(pool_optional_target, 0)"
    remove_column :challenges, :pool_optional_target

    remove_column :challenge_pool_games, :added_at
    remove_check_constraint :challenge_pool_games, name: "ck_challenge_pool_games_inclusion"
    execute "UPDATE challenge_pool_games SET inclusion = 'include' WHERE inclusion IN ('core', 'optional')"
    add_check_constraint :challenge_pool_games, "inclusion IN ('include', 'exclude')",
      name: "ck_challenge_pool_games_inclusion"
  end
end
