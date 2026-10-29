# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/public/winners', type: :request do
  path '/api/v1/public/winners' do
    get 'List recent GOTM winners (public)' do
      tags 'Public'
      description 'The winning games of the latest 24 rounds, for the logged-out landing page. Public — does not ' \
                  'require authentication — so it carries club content only: no member data, Reddit URLs or ' \
                  'Discord ids. One item per winning game, newest round first, GOTM before NR-GOTM, ' \
                  '`game_index` order within a track. NR-GOTM "N/A" placeholders are omitted. `meta.rounds` is ' \
                  'the number of rounds covered. Cached for 10 minutes (`Cache-Control: public, max-age=600`); ' \
                  'a new round busts the server-side cache.'
      produces 'application/json'
      security []

      response '200', 'recent winners' do
        header 'Cache-Control', schema: { type: :string }, description: 'max-age=600, public'
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/PublicWinner' } },
          meta: { type: :object, required: %w[rounds], properties: {
            rounds: { type: :integer, example: 24 }
          } }
        }
      end
    end
  end
end
