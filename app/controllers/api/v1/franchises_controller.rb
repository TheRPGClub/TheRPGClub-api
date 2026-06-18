# frozen_string_literal: true

module Api
  module V1
    class FranchisesController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbFranchise, resource: FranchiseResource, igdb_id_column: :igdb_franchise_id
    end
  end
end
