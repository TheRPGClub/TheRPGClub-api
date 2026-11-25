# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/franchise_suggestions', type: :request do
  path '/api/v1/games/{id}/franchise_suggestions' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    get 'Franchise suggestions for a game' do
      tags 'Franchises'
      description 'Up to three Franchises the game probably belongs to, for Game Edit (ticket api#489). A ' \
                  'Franchise is suggested when the game\'s IGDB Series has its name (`series_name`), other games ' \
                  'in that Series are linked to it (`series_links`), or the game\'s title contains its name as ' \
                  'whole words (`title_match`). Franchises the game is linked to or was unlinked from by hand, ' \
                  'and merged ones, are left out. Ordered by the strongest reason (in that order), then more ' \
                  'reasons, more linked Series games and longer names. Each has a likely `role`: `add_on` (with ' \
                  'the parent) when the game\'s parent game is in that Franchise, else `mainline` when most of ' \
                  'its linked Series games are Mainline there or, with none, when the title starts with the ' \
                  'Franchise\'s name, else `other` (a Spin-off). Regulars and above (the acting member\'s stored ' \
                  'roles).'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member it acts for.'

      response '200', 'suggestions, best first (at most three)' do
        schema type: :object, required: %w[data], properties: {
          data: { type: :array, maxItems: 3, items: { '$ref' => '#/components/schemas/FranchiseSuggestion' } }
        }
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: a member below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
