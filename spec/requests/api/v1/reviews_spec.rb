# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/reviews', type: :request do
  # The client-writable UserGameReview columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create. Unique per (user, game).' },
    rating: { type: :integer, nullable: true, minimum: 0, maximum: 100,
              description: 'Score, 0..100. A Draft may have none; publishing needs one (422 `rating_required`).' },
    title: { type: :string, nullable: true, maxLength: 120, description: 'Optional short title. Omit to leave unchanged; send null to clear.' },
    body: { type: :object, nullable: true, description: 'Optional structured review body (free-form JSON).' },
    facets: { allOf: [ { '$ref' => '#/components/schemas/ReviewFacets' } ], nullable: true,
              description: 'Optional per-category scorecard. Omit or send null for a quick take; ' \
                           '`{"order": []}` is stored as null.' }
  }

  path '/api/v1/users/{user_id}/reviews' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s reviews' do
      tags 'Reviews'
      description 'Open to any authenticated caller. Returns the member\'s Published Reviews in the curated ' \
                  'shape with the game embedded, newest first. Drafts are never listed here (nor counted in ' \
                  '`meta.count`), whoever asks, their author included.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'reviews list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReviewEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Write a review' do
      tags 'Reviews'
      description 'Owner-only. Creates a Draft: only `gamedb_game_id` is required, and a Draft may have no ' \
                  'score yet. With `publish: true` (the quick take) it is created and published in one call, ' \
                  'refused with 422 `rating_required` without a `rating`. A member has at most one Review per ' \
                  'game, and a Draft counts (unique per (user, game)).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: writable.merge(
              publish: { type: :boolean, description: 'True to publish on create (the quick take). Defaults to false (a Draft).' }
            ),
            required: %w[gamedb_game_id]
          }
        },
        required: %w[data]
      }

      response '201', 'review created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed, or `rating_required` when publishing without a score' do
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

  path '/api/v1/users/{user_id}/reviews/drafts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a member\'s Drafts' do
      tags 'Reviews'
      description 'The member\'s Draft Reviews, newest last-touched (`updated_at`) first, with the game and its ' \
                  'GOTM / NR-GOTM track embedded. Readable only by the author and Admins signed in with Discord; ' \
                  'anyone else, the service included, gets 403. Published Reviews never appear here.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'drafts list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReviewDraftEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '403', 'forbidden: the caller is neither the author nor an Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'Reviews is not available to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/reviews' do
    get 'The Review Feed' do
      tags 'Reviews'
      description 'The Review Feed, also behind the Latest Reviews Dashboard Panel: every member\'s Published ' \
                  'Reviews, newest published first (by `published_at`), each with its author and its game ' \
                  '(with the GOTM / NR-GOTM track flags). Open to any authenticated caller who can use ' \
                  'Reviews. Drafts are never listed here, whoever asks, and members who have left the server ' \
                  '(`server_left_at` set) are left out. Every entry is `kind: review` for now; Published ' \
                  'Revisions will join as their own `kind: revision` entries.'
      produces 'application/json'
      parameter name: :written, in: :query, schema: { type: :boolean }, required: false,
        description: 'Written only: true keeps only the entries with text (`written: true`), dropping the ' \
                     'score-only quick takes. `meta.count` counts the filtered list.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'review feed' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReviewFeedEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'Reviews is not available to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/reviews/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameReview review_id.'

    get 'Show a review' do
      tags 'Reviews'
      description 'A Published Review, for any authenticated caller. A Draft is readable only by its author ' \
                  'and Admins; anyone else, the service included, gets 404.'
      produces 'application/json'

      response '200', 'review detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '404', 'not found, or a Draft the caller may not read' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a review' do
      tags 'Reviews'
      description 'Owner-only. Partial update: send any subset of the writable columns. `published_at` is not ' \
                  'writable (publish with `POST /reviews/{id}/publish`; a Published Review never goes back to ' \
                  'Draft), and a Published Review\'s score cannot be cleared (422 `rating_required`). An Edit to a ' \
                  'Published Review may change its score only until `score_locks_at`, 7 days after publishing ' \
                  '(422 `score_locked` after that; ADR 0013); title, text and scorecard stay editable. An Edit ' \
                  'more than an hour after publishing sets `edited_at`. A Draft\'s score changes freely.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed, `rating_required` (clearing a Published score) or `score_locked` (changing the score more than 7 days after publishing)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a review (alias)' do
      tags 'Reviews'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a review' do
      tags 'Reviews'
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

  path '/api/v1/reviews/{id}/publish' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameReview review_id.'

    post 'Publish a review' do
      tags 'Reviews'
      description 'Owner-only. Publishes a Draft, setting `published_at`. Refused with 422 `rating_required` ' \
                  'without a score. Not reversible; publishing a Published Review changes nothing and keeps ' \
                  'its first publish date.'
      produces 'application/json'

      response '200', 'published' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '403', 'forbidden: caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`rating_required`: the Draft has no score' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
