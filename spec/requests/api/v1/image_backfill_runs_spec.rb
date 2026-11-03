# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/image_backfill_runs', type: :request do
  path '/api/v1/image_backfill_runs' do
    post 'Start an image backfill' do
      tags 'Image Backfill'
      description 'Superadmin only (the service token passes too). Queues a run that imports IGDB ' \
                  'images for every game with no stored images, as the bot\'s ' \
                  '`/superadmin download-missing-images` did. A game with no IGDB id counts as ' \
                  '`skipped`, an import error as `failed` (the latest in `last_error`); missing IGDB ' \
                  'or Backblaze configuration fails the run. Poll the run for progress. Refused ' \
                  'with 409 while a run is queued or running; a run that has not reported ' \
                  'progress for 30 minutes is marked failed and no longer blocks a new one.'
      produces 'application/json'

      response '201', 'run queued' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ImageBackfillRun' } },
          required: %w[data]
      end

      response '409', 'a run is already queued or running (`image_backfill_in_progress`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/image_backfill_runs/latest' do
    get 'Get the latest image backfill run' do
      tags 'Image Backfill'
      description 'Superadmin only (the service token passes too). The newest run, with its progress.'
      produces 'application/json'

      response '200', 'the newest run' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ImageBackfillRun' } },
          required: %w[data]
      end

      response '404', 'no run yet' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/image_backfill_runs/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'ImageBackfillRun id.'

    get 'Get an image backfill run' do
      tags 'Image Backfill'
      description 'Superadmin only (the service token passes too). One run, with its progress.'
      produces 'application/json'

      response '200', 'the run' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ImageBackfillRun' } },
          required: %w[data]
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
