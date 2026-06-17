# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/games', type: :request do
  # The relations payload (GamesController#relations_data), reused by both
  # GET /games/{id}/relations and the `relations` slice of the profile.
  relations_shape = {
    type: :object,
    properties: {
      platforms:    { type: :array, items: { '$ref' => '#/components/schemas/Platform' } },
      releases:     { type: :array, items: { '$ref' => '#/components/schemas/Release' } },
      companies:    { type: :array, items: { '$ref' => '#/components/schemas/GameCompany' } },
      collection:   { allOf: [ { '$ref' => '#/components/schemas/Collection' } ], nullable: true },
      franchises:   { type: :array, items: { '$ref' => '#/components/schemas/Franchise' } },
      genres:       { type: :array, items: { '$ref' => '#/components/schemas/Genre' } },
      engines:      { type: :array, items: { '$ref' => '#/components/schemas/Engine' } },
      modes:        { type: :array, items: { '$ref' => '#/components/schemas/Mode' } },
      perspectives: { type: :array, items: { '$ref' => '#/components/schemas/Perspective' } },
      themes:       { type: :array, items: { '$ref' => '#/components/schemas/Theme' } },
      alternates:   { type: :array, items: { '$ref' => '#/components/schemas/Game' } }
    }
  }

  # The game record (GameResource) plus the GOTM/NR-GOTM month-year fields the
  # controller folds in (GamesController#game_record_data), reused by #show and
  # the `game` slice of the profile.
  game_record = {
    allOf: [
      { '$ref' => '#/components/schemas/Game' },
      {
        type: :object,
        properties: {
          gotm_month_year: { type: :string, nullable: true },
          nr_gotm_month_year: { type: :string, nullable: true }
        }
      }
    ]
  }

  path '/api/v1/games' do
    get 'List games' do
      tags 'Games'
      description 'Returns games from the local GameDB. Supports search, a `winner` filter for GOTM / ' \
                  'Non-Retro GOTM history, and taxonomy filters (genre/engine/theme/perspective/mode/franchise/company). ' \
                  'Taxonomy params AND across dimensions; repeat one (`genre_id[]=1&genre_id[]=2`) to match any of several. ' \
                  'Discover valid ids via the `/genres`, `/themes`, … endpoints.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Full-text search against game titles.'
      parameter name: :winner, in: :query, schema: { type: :string, enum: %w[gotm nr_gotm any] }, required: false,
        description: 'Filter to past GOTM winners, Non-Retro GOTM winners, or either.'
      parameter name: :genre_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games in this genre id (repeat to match any of several).'
      parameter name: :engine_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games using this engine id (repeat to match any of several).'
      parameter name: :theme_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games in this theme id (repeat to match any of several).'
      parameter name: :perspective_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games in this perspective id (repeat to match any of several).'
      parameter name: :mode_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games in this mode id (repeat to match any of several).'
      parameter name: :franchise_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games in this franchise id (repeat to match any of several).'
      parameter name: :company_id, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } }, description: 'Filter to games involving this company id (repeat to match any of several).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 25, maximum: 100 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 100 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'games list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Game' } },
          meta: {
            allOf: [
              { '$ref' => '#/components/schemas/PaginationMeta' },
              { type: :object, properties: { resource: { type: :string, example: 'gamedb_games' } } }
            ]
          }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a game from IGDB' do
      tags 'Games'
      description 'Admin/service-only. Creates a game from IGDB by `igdb_id`: fetches the full IGDB ' \
                  'payload, upserts the game row plus its taxonomy (genres, themes, perspectives, modes, ' \
                  'engines, franchises, platforms, developer/publisher companies, collection) and releases ' \
                  '(one per platform, earliest dated; Japan-only releases are skipped; `format` is left ' \
                  'null), then imports its cover/artwork/logo images into Backblaze through the same ' \
                  'importer the jobs use. Idempotent on `igdb_id`: re-POSTing an existing game refreshes ' \
                  'it and returns 200 instead of 201. Discover ids via `GET /api/v1/igdb/search`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          igdb_id: { type: :integer, description: 'The IGDB game id to import.' }
        },
        required: %w[igdb_id]
      }

      response '201', 'game created' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Game' },
          images: { type: :object, additionalProperties: true, description: 'The image-import result (cover/artwork/logo diagnostics); shape mirrors the importer\'s output.' }
        }
      end

      response '200', 'existing game refreshed (idempotent)' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Game' },
          images: { type: :object, additionalProperties: true, description: 'The image-import result (cover/artwork/logo diagnostics).' }
        }
      end

      response '400', 'missing or non-integer `igdb_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'IGDB game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unprocessable (IGDB/Backblaze not configured, invalid image)' do
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

  path '/api/v1/games/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    get 'Show game' do
      tags 'Games'
      description 'Returns a game with related GOTM/NR-GOTM month info plus now-playing and completion previews.'
      produces 'application/json'

      response '200', 'game detail' do
        schema type: :object, properties: {
          data: {
            allOf: [
              { '$ref' => '#/components/schemas/Game' },
              {
                type: :object,
                properties: {
                  gotm_month_year: { type: :string, nullable: true },
                  nr_gotm_month_year: { type: :string, nullable: true },
                  now_playing: { type: :array, items: { '$ref' => '#/components/schemas/NowPlayingUserEntry' } },
                  completions: { type: :array, items: { '$ref' => '#/components/schemas/CompletionUserEntry' } }
                }
              }
            ]
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
        schema type: :object, properties: {
          data: { type: :object, additionalProperties: true, description: 'The image-import result (per-kind diagnostics); shape mirrors the importer\'s output.' }
        }
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
      description 'Returns platforms, releases, companies, collection (series), franchises, genres, engines, modes, perspectives, themes, and alternate titles for a game.'
      produces 'application/json'

      response '200', 'game relations' do
        schema type: :object, properties: { data: relations_shape }
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/profile' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true

    get 'Show aggregate game profile' do
      tags 'Games'
      description 'One aggregate payload for the bot\'s game view: the game record (same shape as ' \
                  '`GET /api/v1/games/{id}`), its relations (same shape as `/relations`), the full ' \
                  '(unpaginated) now-playing / completions / threads lists, the resolved primary image ' \
                  '(nullable), and the GOTM/NR-GOTM associations, collection owners and HowLongToBeat ' \
                  'cache row (nullable). Collapses six HTTP calls plus three direct-SQL reads into one request.'
      produces 'application/json'

      response '200', 'game profile' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              game:        game_record,
              relations:   relations_shape,
              now_playing: { type: :array, items: { '$ref' => '#/components/schemas/NowPlayingUserEntry' } },
              completions: { type: :array, items: { '$ref' => '#/components/schemas/CompletionUserEntry' } },
              threads:     { type: :array, items: { '$ref' => '#/components/schemas/Thread' } },
              primary_image: {
                type: :object, nullable: true,
                properties: { url: { type: :string } }
              },
              associations: {
                type: :object,
                properties: {
                  gotm_wins:           { type: :array, items: { '$ref' => '#/components/schemas/GotmWin' } },
                  nr_gotm_wins:        { type: :array, items: { '$ref' => '#/components/schemas/GotmWin' } },
                  gotm_nominations:    { type: :array, items: { '$ref' => '#/components/schemas/GotmNominationSummary' } },
                  nr_gotm_nominations: { type: :array, items: { '$ref' => '#/components/schemas/GotmNominationSummary' } }
                }
              },
              collection_owners: { type: :array, items: { '$ref' => '#/components/schemas/CollectionOwner' } },
              hltb:              { allOf: [ { '$ref' => '#/components/schemas/Hltb' } ], nullable: true }
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
          data: { type: :array, items: { '$ref' => '#/components/schemas/Release' } }
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
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'now-playing entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NowPlayingUserEntry' } },
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
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'completions for game' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CompletionUserEntry' } },
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
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'reviews for game' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReviewUserEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
