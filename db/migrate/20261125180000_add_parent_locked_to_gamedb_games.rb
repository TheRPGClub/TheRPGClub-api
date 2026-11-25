# frozen_string_literal: true

# A hand-set Add-on parent (GLOSSARY.md "Add-on"): Regulars and above can make
# a game an Add-on of another game, or stop it being one, on the Franchise
# editor (Gamedb::FranchiseEditor).
#
# - `gamedb_games.parent_locked` marks that the parent (`parent_igdb_id`,
#   `parent_game_name`, both null for "not an Add-on") was set by hand, so
#   IGDB re-imports (Gamedb::IgdbGameImporter) keep it, as
#   `gamedb_franchises.name_locked` does for a renamed Franchise. Every
#   existing parent came from IGDB.
# - The Franchise history gains the `parent` action.
class AddParentLockedToGamedbGames < ActiveRecord::Migration[8.1]
  OLD_ACTIONS = %w[link unlink mainline_on mainline_off create rename merge delete].freeze
  NEW_ACTIONS = %w[link unlink mainline_on mainline_off parent create rename merge delete].freeze

  def up
    add_column :gamedb_games, :parent_locked, :boolean, null: false, default: false
    replace_action_check(NEW_ACTIONS)
  end

  def down
    execute "DELETE FROM gamedb_franchise_changes WHERE action = 'parent'"
    replace_action_check(OLD_ACTIONS)
    remove_column :gamedb_games, :parent_locked
  end

  private

  def replace_action_check(actions)
    remove_check_constraint :gamedb_franchise_changes, name: "ck_gamedb_franchise_changes_action"
    add_check_constraint :gamedb_franchise_changes, "action IN (#{actions.map { |a| "'#{a}'" }.join(', ')})",
      name: "ck_gamedb_franchise_changes_action"
  end
end
