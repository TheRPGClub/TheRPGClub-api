# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/roadmap', type: :request do
  path '/api/v1/roadmap' do
    get 'Read the Roadmap' do
      tags 'Roadmap'
      description 'The Roadmap (spec api#505): `milestones` are the open Milestones in staff order, each with its ' \
                  'Roadmap Items in staff order (Shipped ones included, ticked as ready); `reached` are the ' \
                  'Reached Milestones, newest Reached first, each with the Roadmap Items that Shipped with it. ' \
                  'Members (any signed-in caller). Belongs to the Roadmap Feature, so a member who cannot use it ' \
                  'gets 404 `not_found` (non-staff in Preview, everyone when Off); the service token is not gated.'
      produces 'application/json'

      response '200', 'the Roadmap' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Roadmap' } }, required: %w[data]
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
