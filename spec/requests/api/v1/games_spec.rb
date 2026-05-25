# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/games', type: :request do
  path '/api/v1/games' do
    get 'List games' do
      tags 'Games'
      description 'Returns games from the local GameDB. Supports search and a `winner` filter for GOTM / Non-Retro GOTM history.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Full-text search against game titles.'
      parameter name: :winner, in: :query, schema: { type: :string, enum: %w[gotm nr_gotm any] }, required: false,
        description: 'Filter to past GOTM winners, Non-Retro GOTM winners, or either.'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 25, minimum: 1, maximum: 100 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0, minimum: 0 }, required: false

      response '200', 'games list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: {
            type: :object,
            properties: {
              resource: { type: :string, example: 'gamedb_games' },
              limit: { type: :integer },
              offset: { type: :integer },
              total: { type: :integer }
            }
          }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    get 'Show game' do
      tags 'Games'
      description 'Returns a game with related GOTM/NR-GOTM month info plus now-playing and completion previews.'
      produces 'application/json'

      response '200', 'game detail' do
        schema type: :object, properties: {
          data: {
            type: :object,
            additionalProperties: true,
            properties: {
              gotm_month_year: { type: :string, nullable: true },
              nr_gotm_month_year: { type: :string, nullable: true },
              now_playing: { type: :array, items: { type: :object, additionalProperties: true } },
              completions: { type: :array, items: { type: :object, additionalProperties: true } }
            }
          }
        }
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/refresh-images' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    post 'Refresh images from IGDB' do
      tags 'Games'
      description 'Re-imports cover/screenshot artwork from IGDB into Backblaze B2 storage. Restricted to admins or the service account.'
      produces 'application/json'

      response '200', 'images refreshed' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'IGDB game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unprocessable (missing IGDB id, invalid image, missing config)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'upstream (IGDB or Backblaze) request failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/relations' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'Show game relations' do
      tags 'Games'
      description 'Returns platforms, releases, companies, franchises, genres, modes, perspectives, themes, and alternate titles for a game.'
      produces 'application/json'

      response '200', 'game relations' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              platforms:    { type: :array, items: { type: :object, additionalProperties: true } },
              releases:     { type: :array, items: { type: :object, additionalProperties: true } },
              companies:    { type: :array, items: { type: :object, additionalProperties: true } },
              franchises:   { type: :array, items: { type: :object, additionalProperties: true } },
              genres:       { type: :array, items: { type: :object, additionalProperties: true } },
              modes:        { type: :array, items: { type: :object, additionalProperties: true } },
              perspectives: { type: :array, items: { type: :object, additionalProperties: true } },
              themes:       { type: :array, items: { type: :object, additionalProperties: true } },
              alternates:   { type: :array, items: { type: :object, additionalProperties: true } }
            }
          }
        }
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/releases' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'List game releases' do
      tags 'Games'
      description 'Returns release rows for a game, sorted by date then platform/region.'
      produces 'application/json'

      response '200', 'releases list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } }
        }
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/now_playing' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'List users currently playing this game' do
      tags 'Games'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false

      response '200', 'now-playing entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/completions' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'List completions for this game' do
      tags 'Games'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false

      response '200', 'completions for game' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/reviews' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'List reviews for this game' do
      tags 'Games'
      description 'Reviews are sorted so those with non-null bodies appear first.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false

      response '200', 'reviews for game' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
