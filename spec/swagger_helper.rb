# frozen_string_literal: true

require 'rails_helper'
require 'rswag/specs'
require_relative 'support/rswag_doc_only'
require_relative 'support/openapi_schemas'

RSpec.configure do |config|
  config.openapi_root = Rails.root.join('swagger').to_s

  config.openapi_specs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.1',
      info: {
        title: 'The RPG Club API',
        version: 'v1',
        description: 'Backend API for The RPG Club. Authentication is performed with a bearer ' \
                     '`UserSessionToken` issued after Discord OAuth, or a service token for the bot.'
      },
      servers: [
        {
          url: '{host}',
          description: 'Development',
          variables: {
            host: {
              default: ENV.fetch('SWAGGER_API_HOST_DEV', 'http://localhost:3000')
            }
          }
        },
        {
          url: '{host}',
          description: 'Production',
          variables: {
            host: {
              default: ENV.fetch('SWAGGER_API_HOST_PROD', 'https://api.example.com')
            }
          }
        }
      ],
      components: {
        securitySchemes: {
          bearerAuth: {
            type: :http,
            scheme: :bearer,
            bearerFormat: 'UserSessionToken',
            description: 'Bearer token issued by `POST /auth/discord/callback` (user session) or ' \
                         'the service-account token used by the Discord bot.'
          }
        },
        # Reusable resource/response component schemas, cross-checked against the
        # models, db/structure.sql and the Alba serializers (#78). Defined in
        # spec/support/openapi_schemas.rb and referenced from the request specs
        # via `$ref` so a resource's response shape is documented exactly once.
        schemas: OpenapiSchemas.definitions
      },
      security: [ { bearerAuth: [] } ],
      paths: {}
    }
  }

  config.openapi_format = :yaml
end
