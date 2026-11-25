# frozen_string_literal: true

# One change to a Franchise in its history (spec api#442, ticket api#444),
# written by Gamedb::FranchiseEditor. `game_id` is set for a change to one
# game's link; `before`/`after` hold the values it changed. A change that
# was undone keeps its row and gets `undone_at`/`undone_by`.
#
# There is no foreign key to the Franchise, so a deleted Franchise's rows
# stay as a record of what happened to it.
class GamedbFranchiseChange < ApplicationRecord
  self.table_name = "gamedb_franchise_changes"

  # `parent` sets or clears a game's Add-on parent by hand. The parent
  # belongs to the game, not the link, so the change is recorded in the
  # history of the Franchise it was made from.
  ACTIONS = %w[link unlink mainline_on mainline_off parent create rename merge delete].freeze
  # Merge and delete can't be undone (spec api#442, "Out of scope"), and
  # undoing a create would be a delete.
  UNDOABLE = %w[link unlink mainline_on mainline_off parent rename].freeze
  GAME_ACTIONS = %w[link unlink mainline_on mainline_off parent].freeze

  belongs_to :game, class_name: "GamedbGame", optional: true, inverse_of: false
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", primary_key: :user_id, optional: true, inverse_of: false

  validates :action, inclusion: { in: ACTIONS }

  def undoable_action? = UNDOABLE.include?(action)

  def game_change? = GAME_ACTIONS.include?(action)

  # Whether a later change that still stands touched what this one changed:
  # the same game's link (or the whole Franchise, by a merge into it) for a
  # link or Mainline change, the game's parent (from any Franchise) for a
  # parent change, the name for a rename.
  def superseded?
    standing = self.class.where(undone_at: nil).where("id > ?", id)
    return standing.where(game_id: game_id, action: "parent").exists? if action == "parent"

    later = standing.where(franchise_id: franchise_id)
    later = if game_change?
      later.where(game_id: game_id).where.not(action: "parent").or(later.where(action: "merge"))
    else
      later.where(action: "rename")
    end
    later.exists?
  end
end
