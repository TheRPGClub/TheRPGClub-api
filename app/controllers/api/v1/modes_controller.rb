# frozen_string_literal: true

module Api
  module V1
    class ModesController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbGameModeDef, resource: ModeResource, igdb_id_column: :igdb_game_mode_id
    end
  end
end
