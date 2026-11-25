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

  ACTIONS = %w[link unlink mainline_on mainline_off create rename merge delete].freeze
  # Merge and delete can't be undone (spec api#442, "Out of scope"), and
  # undoing a create would be a delete.
  UNDOABLE = %w[link unlink mainline_on mainline_off rename].freeze
  GAME_ACTIONS = %w[link unlink mainline_on mainline_off].freeze

  belongs_to :game, class_name: "GamedbGame", optional: true, inverse_of: false
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", primary_key: :user_id, optional: true, inverse_of: false

  validates :action, inclusion: { in: ACTIONS }

  def undoable_action? = UNDOABLE.include?(action)

  def game_change? = GAME_ACTIONS.include?(action)

  # Whether a later change that still stands touched what this one changed:
  # the same game (or the whole Franchise, by a merge into it) for a game
  # change, the name for a rename.
  def superseded?
    later = self.class.where(franchise_id: franchise_id, undone_at: nil).where("id > ?", id)
    later = game_change? ? later.where(game_id: game_id).or(later.where(action: "merge")) : later.where(action: "rename")
    later.exists?
  end
end
