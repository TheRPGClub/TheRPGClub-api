# frozen_string_literal: true

# What the collection CSV, Steam and Completionator import item controllers
# share (#289, #290, #291):
#
# - `load_actionable_item`: a before_action that loads @item and renders
#   409 `import_not_active` / `item_not_pending` unless the item is pending
#   and its import active.
# - `igdb_candidates`: the GET .../igdb_candidates?q= action
#   (Imports::IgdbCandidateSearch on `q`, else the item's title column).
# - `game_choice(data)` / `chosen_game(game_id, igdb_id)` /
#   `render_game_error(error)`: the "exactly one of game_id or igdb_id" pick,
#   resolved to a GameDB game (an igdb_id via Imports::IgdbGameResolver), with
#   IGDB_ERROR_STATUS for the failures.
#
#   class Api::V1::SteamCollectionImportItemsController < ApplicationController
#     include ImportItemActions
#     import_item_actions RpgClubSteamCollectionImportItem, title: :steam_app_name,
#       actionable: %i[apply_selection skip remap]
#   end
#
# The controller checks the owner (require_owner!) before these run.
module ImportItemActions
  extend ActiveSupport::Concern

  # HTTP status per Imports::IgdbGameResolver error code.
  IGDB_ERROR_STATUS = {
    "invalid_igdb_id" => :unprocessable_content,
    "igdb_not_configured" => :unprocessable_content,
    "igdb_game_not_found" => :not_found,
    "igdb_request_failed" => :bad_gateway
  }.freeze

  class_methods do
    # @param model [Class] the import item model
    # @param title [Symbol] the item column igdb_candidates searches without `q`
    # @param actionable [Array<Symbol>] the actions that need a pending item
    #   of an active import (loaded into @item)
    def import_item_actions(model, title:, actionable:)
      define_method(:import_item_model) { model }
      define_method(:import_item_title) { |item| item.public_send(title) }
      private :import_item_model, :import_item_title

      before_action :load_actionable_item, only: actionable
    end
  end

  # GET .../import_items/:id/igdb_candidates?q=
  #
  # IGDB suggestions for the item, searched by progressive title variants;
  # each hit carries `already_imported`.
  def igdb_candidates
    item = import_item_model.find(params[:id])
    title = params[:q].presence || import_item_title(item)

    render json: { data: Imports::IgdbCandidateSearch.new.search(title) }
  rescue Igdb::Client::ConfigurationError
    render json: { error: "igdb_not_configured" }, status: :unprocessable_content
  rescue Igdb::Client::RequestError
    render json: { error: "igdb_request_failed" }, status: :bad_gateway
  end

  private

  def load_actionable_item
    @item = import_item_model.find(params[:id])
    error =
      if @item.import.status != "active" then "import_not_active"
      elsif @item.status != "pending" then "item_not_pending"
      end
    render json: { error: error }, status: :conflict if error
  end

  # [game_id, igdb_id] from the body, or nil after rendering 422
  # `game_id_or_igdb_id_required` unless exactly one is present.
  def game_choice(data)
    game_id, igdb_id = data.values_at("game_id", "igdb_id").map(&:presence)
    return [ game_id, igdb_id ] unless game_id.nil? == igdb_id.nil?

    render json: { error: "game_id_or_igdb_id_required" }, status: :unprocessable_content
    nil
  end

  # [game, nil] or [nil, error code]. An igdb_id not yet in GameDB is
  # imported, so call this inside the test-mode rollback.
  def chosen_game(game_id, igdb_id)
    game_id ? find_game(game_id) : import_igdb_game(igdb_id)
  end

  def render_game_error(error)
    render json: { error: error }, status: error == "game_not_found" ? :not_found : IGDB_ERROR_STATUS.fetch(error, :unprocessable_content)
  end

  def find_game(raw_id)
    game_id = Integer(raw_id.to_s, 10, exception: false)
    game = game_id&.positive? && GamedbGame.find_by(game_id: game_id)
    game ? [ game, nil ] : [ nil, "game_not_found" ]
  end

  def import_igdb_game(raw_id)
    result = Imports::IgdbGameResolver.new.resolve(raw_id)
    [ result.game, result.error ]
  end
end
