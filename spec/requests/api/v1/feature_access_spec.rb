# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/feature_access', type: :request do
  path '/api/v1/users/{user_id}/feature_access' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member acting through the bot.'

    get "Look up a Discord user's Feature access" do
      tags 'Features'
      description "Service-only. For the bot's feature gate: every Feature's Feature Flag state and whether this " \
                  'Discord user can use it (Live: everyone; Preview: Admins and Superadmins; Off: nobody). ' \
                  "Staff is read from the member's stored roles, Admin or the dev role (Superadmin), which " \
                  'sign-in and the bot\'s role reports (`PUT /users/{user_id}/roles`) keep current. A Discord ' \
                  'user with no member record is not staff. Feature Preferences never affect this lookup.'
      produces 'application/json'

      response '200', 'Feature access for the user' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FeatureAccess' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
