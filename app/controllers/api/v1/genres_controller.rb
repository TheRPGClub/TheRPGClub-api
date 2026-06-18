# frozen_string_literal: true

module Api
  module V1
    class GenresController < ApplicationController
      include TaxonomyEndpoints

      serves_taxonomy GamedbGenre, resource: GenreResource, igdb_id_column: :igdb_genre_id
    end
  end
end
