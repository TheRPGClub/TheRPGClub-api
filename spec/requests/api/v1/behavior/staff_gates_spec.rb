# frozen_string_literal: true

require "rails_helper"

# The named role gates (StaffGates) every controller can use to match the
# bot's role checks. Production endpoints use only some gates, so the
# examples mount a probe controller with one action per gate and exercise it
# over HTTP like any other endpoint.
class StaffGatesProbeController < ApplicationController
  before_action :require_member_role!, only: :member
  before_action :require_member_or_staff!, only: :member_or_staff
  before_action :require_regular_role!, only: :regular
  before_action :require_regular_or_staff!, only: :regular_or_staff
  before_action :require_moderator_or_above!, only: :moderator
  before_action :require_admin_or_above!, only: :admin
  before_action :require_superadmin!, only: :superadmin

  %i[member member_or_staff regular regular_or_staff moderator admin superadmin].each do |gate|
    define_method(gate) { render json: { ok: gate } }
  end

  # Checks two gates in one request, as an endpoint combining them would.
  def moderator_then_admin
    render json: { moderator: moderator_or_above?, admin: admin_or_above?, admin_or_service: admin_or_service? }
  end
end

RSpec.describe "staff gates behavior", type: :request do
  around do |example|
    with_routing do |routes|
      routes.draw do
        %w[member member_or_staff regular regular_or_staff moderator admin superadmin].each do |gate|
          get "/staff_gates_probe/#{gate}", to: "staff_gates_probe##{gate}"
        end
        get "/staff_gates_probe/moderator_then_admin", to: "staff_gates_probe#moderator_then_admin"
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
    "a Members role holder" => [ { role_member: true }, {}, %w[member member_or_staff] ],
    "a Regulars role holder" => [ { role_regular: true }, {}, %w[regular regular_or_staff] ],
    "a Moderator" => [ { role_moderator: true }, {}, %w[member_or_staff regular_or_staff moderator] ],
    "an Admin" => [ { role_admin: true }, {}, %w[member_or_staff regular_or_staff moderator admin] ],
    "a Superadmin" => [ {}, { is_dev: true }, %w[member_or_staff regular_or_staff moderator admin superadmin] ]
  }

  callers.each do |label, (flags, token_flags, allowed)|
    describe "for #{label}" do
      let(:headers) { auth_headers_for(create(:user, **flags), **token_flags) }

      %w[member member_or_staff regular regular_or_staff moderator admin superadmin].each do |gate|
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
    %w[member member_or_staff regular regular_or_staff moderator admin superadmin].each do |gate|
      get "/staff_gates_probe/#{gate}", headers: service_headers

      expect(response).to have_http_status(:ok), "service refused by the #{gate} gate"
    end
  end

  it "reads the member's role flags once per request, however many gates it checks" do
    headers = auth_headers_for(create(:user, role_admin: true))
    user_queries = lambda do |path|
      count = 0
      counter = ->(*, payload) { count += 1 if payload[:sql].include?("rpg_club_users") }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path, headers: headers }
      count
    end

    single = user_queries.call("/staff_gates_probe/moderator")
    combined = user_queries.call("/staff_gates_probe/moderator_then_admin")

    expect(json).to eq("moderator" => true, "admin" => true, "admin_or_service" => true)
    expect(combined).to eq(single)
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
