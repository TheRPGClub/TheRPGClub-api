# frozen_string_literal: true

module Api
  module V1
    class EnginesController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbEngine, resource: EngineResource, igdb_id_column: :igdb_engine_id
    end
  end
end
