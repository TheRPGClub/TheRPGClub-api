# frozen_string_literal: true

# A row of a Franchise's history (GamedbFranchiseChange), with the game's
# title, the names of who made and who undid it, and `can_undo` for the
# viewer. Takes `params`: `titles` (game_id => title), `names` (user_id =>
# username), `can_edit` (the viewer may undo) and `undoable` (the ids
# nothing has superseded).
class FranchiseChangeResource
  include BaseResource

  attribute(:change_id, &:id)
  attributes :franchise_id, :game_id
  attribute(:game_title) { |change| params.fetch(:titles, {})[change.game_id] }
  attributes :action, :before, :after, :user_id
  attribute(:username) { |change| params.fetch(:names, {})[change.user_id] }
  attributes :created_at, :undone_at, :undone_by
  attribute(:undone_by_username) { |change| params.fetch(:names, {})[change.undone_by] }
  attribute(:can_undo) do |change|
    params[:can_edit] && change.undone_at.nil? && params.fetch(:undoable, Set.new).include?(change.id)
  end
end
