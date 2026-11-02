# frozen_string_literal: true

require "rails_helper"

# The named role gates (StaffGates) every controller can use to match the
# bot's role checks. No production endpoint uses the new gates yet, so the
# examples mount a probe controller with one action per gate and exercise it
# over HTTP like any other endpoint.
class StaffGatesProbeController < ApplicationController
  before_action :require_member_role!, only: :member
  before_action :require_member_or_above!, only: :member_or_above
  before_action :require_regular_role!, only: :regular
  before_action :require_moderator_or_above!, only: :moderator
  before_action :require_admin_or_above!, only: :admin
  before_action :require_superadmin!, only: :superadmin

  %i[member member_or_above regular moderator admin superadmin].each do |gate|
    define_method(gate) { render json: { ok: gate } }
  end
end

RSpec.describe "staff gates behavior", type: :request do
  around do |example|
    with_routing do |routes|
      routes.draw do
        %w[member member_or_above regular moderator admin superadmin].each do |gate|
          get "/staff_gates_probe/#{gate}", to: "staff_gates_probe##{gate}"
        end
        # with_routing replaces the app's routes, so redraw the role report.
        put "/api/v1/users/:user_id/roles", to: "api/v1/user_roles#update"
      end
      example.run
    end
  end

  # Which gates each caller passes. Superadmin is the session token's `dev`
  # flag; every other staff signal is a role flag on the member's record.
  callers = {
    "a plain member" => [ {}, {}, [] ],
    "a Members role holder" => [ { role_member: true }, {}, %w[member member_or_above] ],
    "a Regulars role holder" => [ { role_regular: true }, {}, %w[regular] ],
    "a Moderator" => [ { role_moderator: true }, {}, %w[member_or_above moderator] ],
    "an Admin" => [ { role_admin: true }, {}, %w[member_or_above moderator admin] ],
    "a Superadmin" => [ {}, { is_dev: true }, %w[member_or_above moderator admin superadmin] ]
  }

  callers.each do |label, (flags, token_flags, allowed)|
    describe "for #{label}" do
      let(:headers) { auth_headers_for(create(:user, **flags), **token_flags) }

      %w[member member_or_above regular moderator admin superadmin].each do |gate|
        expected = allowed.include?(gate) ? :ok : :forbidden

        it "#{expected == :ok ? 'passes' : 'refuses'} the #{gate} gate" do
          get "/staff_gates_probe/#{gate}", headers: headers

          expect(response).to have_http_status(expected)
          expect(json).to eq("error" => "forbidden") if expected == :forbidden
        end
      end
    end
  end

  it "passes the service principal through every gate" do
    %w[member member_or_above regular moderator admin superadmin].each do |gate|
      get "/staff_gates_probe/#{gate}", headers: service_headers

      expect(response).to have_http_status(:ok), "service refused by the #{gate} gate"
    end
  end

  it "requires authentication before any gate" do
    get "/staff_gates_probe/member"

    expect(response).to have_http_status(:unauthorized)
  end

  it "follows a role report without a new sign-in" do
    user = create(:user)
    headers = auth_headers_for(user)

    get "/staff_gates_probe/moderator", headers: headers
    expect(response).to have_http_status(:forbidden)

    put "/api/v1/users/#{user.user_id}/roles", params: { data: { role_ids: [ DiscordRoles::MODERATOR ] } },
      headers: service_headers, as: :json
    get "/staff_gates_probe/moderator", headers: headers
    expect(response).to have_http_status(:ok)

    put "/api/v1/users/#{user.user_id}/roles", params: { data: { role_ids: [] } },
      headers: service_headers, as: :json
    get "/staff_gates_probe/moderator", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end
