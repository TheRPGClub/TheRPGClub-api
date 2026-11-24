# frozen_string_literal: true

# A Game List as the API serves it (spec api#442, ticket api#446).
#
#   club             true when the club owns it (owner is null)
#   owner            the member who owns it
#   taken_over_from  the member the club took it over from (ticket api#448)
#   entry_count      how many games it holds
#   preview_games    its first 4 games in its own order, { game_id, title, cover_url }
#   viewer           what the acting member may do with it (GameLists::Actor)
#   entries          (a single list only) every game, in its sort's order
#
# Pass `params[:actor]`, and for a page of lists `params[:counts]` and
# `params[:previews]` (GameLists::Overview.of the page); a single list reads
# its own. `params[:detail]` adds `entries`. Load lists through
# GameListResource.preloaded.
class GameListResource
  include BaseResource

  attributes :id, :name, :description, :visibility, :sort

  attribute :club, &:club?

  attribute :owner do |list|
    GameLists.member(list.owner)
  end

  attribute :taken_over_from do |list|
    GameLists.member(list.taken_over_from)
  end

  attributes :taken_over_at

  attribute :entry_count do |list|
    (params[:counts] || overview(list)[:counts]).fetch(list.id, 0)
  end

  attribute :preview_games do |list|
    (params[:previews] || overview(list)[:previews]).fetch(list.id, [])
  end

  attribute :viewer do |list|
    params.fetch(:actor).viewer(list)
  end

  attributes :created_at, :updated_at

  attribute :entries, if: proc { params[:detail] } do |list|
    entries = list.entries.joins(:game).order(GameLists.entry_order(list.sort)).preload(game: :images)
    GameListEntryResource.new(entries).serializable_hash
  end

  def self.preloaded(scope) = scope.preload(:owner, :taken_over_from)

  private

  def overview(list)
    @overview ||= {}
    @overview[list.id] ||= GameLists::Overview.of([ list ])
  end
end
