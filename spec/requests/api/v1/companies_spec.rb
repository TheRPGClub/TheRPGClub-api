# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/companies', type: :request do
  path '/api/v1/companies' do
    get 'List companies' do
      tags 'Companies'
      description 'Returns the IGDB-curated companies (developers/publishers). ' \
                  'Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'companies list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Company' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/companies/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbCompany id.'

    get 'Show company' do
      tags 'Companies'
      produces 'application/json'

      response '200', 'company' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Company' } }
      end

      response '404', 'company not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
