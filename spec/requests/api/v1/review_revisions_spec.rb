# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/review_revisions', type: :request do
  # The client-writable Revision columns. `review_id` comes from the path.
  writable = {
    rating: { type: :integer, nullable: true, minimum: 0, maximum: 100,
              description: 'Score, 0..100. A Draft Revision may have none; publishing needs one ' \
                           '(422 `rating_required`).' },
    title: { type: :string, nullable: true, maxLength: 120, description: 'Optional short title.' },
    body: { type: :object, nullable: true, description: 'Optional structured body (free-form JSON).' },
    facets: { allOf: [ { '$ref' => '#/components/schemas/ReviewFacets' } ], nullable: true,
              description: 'Optional scorecard, validated like a Review\'s.' }
  }

  path '/api/v1/reviews/{review_id}/revisions' do
    parameter name: :review_id, in: :path, schema: { type: :string }, required: true,
      description: 'UserGameReview review_id.'

    get 'List a review\'s Revisions' do
      tags 'Reviews'
      description 'The Review\'s Published Revisions in publish order, each with the score it replaced, then its ' \
                  'Draft Revision for its author and Admins signed in with Discord. A Draft Review reads as ' \
                  'not found for anyone else, the service included.'
      produces 'application/json'

      response '200', 'revisions' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReviewRevision' } }
        }
      end

      response '404', 'not found, or a Draft Review the caller may not read' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Revisit a review' do
      tags 'Reviews'
      description 'Owner-only. Starts a Draft Revision of a Published Review; every field is optional. Refused ' \
                  'with 422 `review_not_published` on a Draft Review, and with 422 `draft_revision_exists` ' \
                  'while the Review already has a Draft Revision (one at a time).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '201', 'Draft Revision created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReviewRevision' } }
      end

      response '403', 'forbidden: caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'review not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`review_not_published`, `draft_revision_exists`, or validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/review_revisions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
      description: 'UserGameReviewRevision revision_id.'

    patch 'Update a Revision' do
      tags 'Reviews'
      description 'Owner-only. Partial update, the autosave of a Draft Revision and the Edit of a Published one. ' \
                  'A Published Revision\'s score cannot be cleared (422 `rating_required`) and may change only ' \
                  'until its own `score_locks_at`, 7 days after it was published (422 `score_locked`; ADR ' \
                  '0013). An Edit more than an hour after it was published sets `edited_at`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReviewRevision' } }
      end

      response '403', 'forbidden: caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed, `rating_required` or `score_locked`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Revision' do
      tags 'Reviews'
      description 'Owner-only. Deleting a Published Revision restores the score before it as the Review\'s ' \
                  'current score.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden: caller is not the owner' do
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

  path '/api/v1/review_revisions/{id}/publish' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
      description: 'UserGameReviewRevision revision_id.'

    post 'Publish a Revision' do
      tags 'Reviews'
      description 'Owner-only. Publishes a Draft Revision, setting `published_at`; its score becomes the ' \
                  'Review\'s current score. Refused with 422 `rating_required` without a score. Not reversible.'
      produces 'application/json'

      response '200', 'published' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReviewRevision' } }
      end

      response '403', 'forbidden: caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`rating_required`: the Draft Revision has no score' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
