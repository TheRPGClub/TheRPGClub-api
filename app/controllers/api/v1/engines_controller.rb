# frozen_string_literal: true

module Api
  module V1
    class EnginesController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbEngine, resource: EngineResource
    end
  end
end
