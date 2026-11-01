# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/achievement_sets', type: :request do
  path '/api/v1/achievement_sets/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true,
              description: 'achievement_sets.id.'

    patch "Fix an Achievement Set's GameDB link" do
      tags 'Achievement Sets'
      description "Admin-only (a role_admin member or a dev; the service token is refused). Sets or clears " \
                  "the set's GameDB game. Sets are linked best-effort when created and an existing link is " \
                  'never overwritten automatically, so this is the manual fix.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              game_id: { type: :integer, nullable: true, description: 'gamedb_games.game_id, or null to unlink. Required.' }
            },
            required: %w[game_id]
          }
        },
        required: %w[data]
      }

      response '200', 'link updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/AchievementSetLink' } }
      end

      response '400', 'missing game_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not an admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'Achievement Set not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unknown GameDB game' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
