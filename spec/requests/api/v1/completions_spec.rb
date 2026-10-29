# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/completions', type: :request do
  # The client-writable UserGameCompletion columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create.' },
    completion_type: { type: :string, description: 'How it was completed (e.g. "main", "100%"). Required on create.' },
    completed_at: { type: :string, format: 'date-time', nullable: true, description: 'When the game was completed.' },
    final_playtime_hrs: { type: :number, nullable: true, description: 'Final playtime in hours.' },
    platform_id: { type: :integer, nullable: true, description: 'Optional platform association.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note.' }
  }

  path '/api/v1/users/{user_id}/completions' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s completions' do
      tags 'Completions'
      description 'Ordered by `completed_at` descending, then `created_at` descending. Open to any ' \
                  'authenticated caller. The optional `game_id`, `platform_id`, `year`, `q`, `completed_after` ' \
                  'and `completed_before` params filter the list (each ANDs in). `meta.count` reflects the ' \
                  'filtered total, so a count-only caller can request `per=1` and read it without ' \
                  'fetching every row.'
      produces 'application/json'
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to completions of this game (`gamedb_game_id`).'
      parameter name: :platform_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to completions on this platform (exact `platform_id`).'
      parameter name: :year, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by completion year (`YYYY`); the literal `unknown` matches entries with no `completed_at`.'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by game title (case-insensitive substring).'
      parameter name: :completed_after, in: :query, schema: { type: :string, format: 'date-time' }, required: false,
        description: 'Only completions with `completed_at` on or after this time.'
      parameter name: :completed_before, in: :query, schema: { type: :string, format: 'date-time' }, required: false,
        description: 'Only completions with `completed_at` on or before this time.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'completions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CompletionEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Record a completion' do
      tags 'Completions'
      description 'Owner-only. `gamedb_game_id` and `completion_type` are required; `completed_at`, ' \
                  '`final_playtime_hrs`, `platform_id` and `note` are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id completion_type] } },
        required: %w[data]
      }

      response '201', 'completion created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/completions/common' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'The left member.'

    get 'List games two members have both completed' do
      tags 'Completions'
      description 'Games that both `user_id` (left) and `other_user_id` (right) have completed, one row ' \
                  'per game with each member\'s latest entry and completion count. Open to any ' \
                  'authenticated caller. Filters match a game when any of either member\'s entries for ' \
                  'it match. `sort` defaults to `date_desc`: date sorts order by `latest_shared_date` ' \
                  '(undated games last, ties by title); title sorts are case-insensitive.'
      produces 'application/json'
      parameter name: :other_user_id, in: :query, schema: { type: :string }, required: true,
        description: 'The right member. Must differ from `user_id`.'
      parameter name: :year, in: :query, schema: { type: :string }, required: false,
        description: 'Keep games with an entry completed in this year (`YYYY`); `unknown` keeps games with an undated entry.'
      parameter name: :platform_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Keep games with an entry on this platform.'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by game title (case-insensitive substring).'
      parameter name: :sort, in: :query, required: false,
        schema: { type: :string, enum: %w[date_desc date_asc title_asc title_desc], default: 'date_desc' }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'common completions' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CommonCompletionEntry' } },
          meta: { '$ref' => '#/components/schemas/CommonCompletionMeta' }
        }
      end

      response '422', 'missing or same-member `other_user_id`, an unknown `sort`, or `invalid_year` / ' \
                      '`invalid_platform_id` for a `year` that is not an integer or `unknown`, or a non-integer `platform_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'either member not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/completions/export' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'Export a user\'s completions as CSV' do
      tags 'Completions'
      description 'Owner-only. Every completion the user has, unpaginated and in the list order ' \
                  '(`completed_at` descending, then `created_at` descending), as a `text/csv` attachment ' \
                  'named `completions.csv`. The columns match the Discord bot\'s export: ' \
                  '`ID,Game ID,Title,Type,Platform ID,Completed Date,Playtime (Hours),Note,Created At`. ' \
                  '`Completed Date` is the UTC date (`YYYY-MM-DD`) and `Created At` is an ISO-8601 UTC ' \
                  'timestamp with milliseconds. Empty values are blank. Fields that contain a comma, ' \
                  'quote or line break are quoted (RFC 4180). A user with no completions gets only the ' \
                  'header row.'
      produces 'text/csv', 'application/json'

      response '200', 'completions CSV' do
        header 'Content-Disposition', schema: { type: :string },
          description: '`attachment; filename="completions.csv"`'
        schema type: :string, format: :binary
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completions/leaderboard' do
    get 'Completion leaderboard' do
      tags 'Completions'
      description 'Active members (`server_left_at` is null) ranked by total completion count, most ' \
                  'first (ties broken by `user_id`). Open to any authenticated caller. The optional ' \
                  '`q` filters to completions of games whose title matches (case-insensitive substring).'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by game title (case-insensitive substring).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'leaderboard' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CompletionLeaderboardEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameCompletion completion_id.'

    get 'Show a completion' do
      tags 'Completions'
      produces 'application/json'

      response '200', 'completion detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a completion' do
      tags 'Completions'
      description 'Owner-only. Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a completion (alias)' do
      tags 'Completions'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a completion' do
      tags 'Completions'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
