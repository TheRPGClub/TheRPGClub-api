# frozen_string_literal: true

module Api
  module V1
    class PerspectivesController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbPerspective, resource: PerspectiveResource, igdb_id_column: :igdb_perspective_id
    end
  end
end
