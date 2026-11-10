# frozen_string_literal: true

require "rails_helper"

# The feature gate (spec #347, ticket #349; docs/adr/0005): a controller
# declares the Feature its endpoints belong to, and a request from someone
# the Feature Flag does not let use that Feature gets 404, as if the endpoint
# did not exist. Live lets everyone in, Preview only Admins and Superadmins,
# Off nobody. The bot's service token is never stopped, because the bot runs
# its own feature gate.
class FeatureGateProbeController < ApplicationController
  feature :journals

  # A role gate after the feature gate, as many Feature endpoints have.
  before_action :require_moderator_or_above!, only: :moderated

  def show
    render json: { ok: true }
  end

  def moderated
    render json: { ok: true }
  end
end

# The same controller shape without a Feature: never gated.
class UngatedProbeController < ApplicationController
  def show
    render json: { ok: true }
  end
end

RSpec.describe "feature gate behavior", type: :request do
  around do |example|
    with_routing do |routes|
      routes.draw do
        get "/feature_gate_probe", to: "feature_gate_probe#show"
        get "/feature_gate_probe/moderated", to: "feature_gate_probe#moderated"
        get "/ungated_probe", to: "ungated_probe#show"
      end
      example.run
    end
  end

  callers = {
    "a member" => [ { role_member: true }, {} ],
    "a Moderator" => [ { role_moderator: true }, {} ],
    "an Admin" => [ { role_admin: true }, {} ],
    "a Superadmin" => [ {}, { is_dev: true } ]
  }

  # Who may use the Feature in each state (the spec's access table).
  allowed = {
    "live" => [ "a member", "a Moderator", "an Admin", "a Superadmin" ],
    "preview" => [ "an Admin", "a Superadmin" ],
    "off" => []
  }

  allowed.each do |state, users|
    context "when the Feature is #{state.capitalize}" do
      before { set_feature_flag("journals", state) }

      callers.each do |label, (flags, token_flags)|
        expected = users.include?(label) ? :ok : :not_found

        it "#{expected == :ok ? 'lets' : 'hides it from'} #{label}" do
          get "/feature_gate_probe", headers: auth_headers_for(create(:user, **flags), **token_flags)

          expect(response).to have_http_status(expected)
          expect(json).to eq("error" => "not_found") if expected == :not_found
        end
      end

      it "lets the bot's service token through" do
        get "/feature_gate_probe", headers: service_headers

        expect(response).to have_http_status(:ok)
      end

      it "leaves an endpoint that belongs to no Feature alone" do
        get "/ungated_probe", headers: auth_headers_for(create(:user))

        expect(response).to have_http_status(:ok)
      end
    end
  end

  it "reads a Feature with no stored state as Preview", feature_flags: :none do
    get "/feature_gate_probe", headers: auth_headers_for(create(:user, role_member: true))
    expect(response).to have_http_status(:not_found)

    get "/feature_gate_probe", headers: auth_headers_for(create(:user, role_admin: true))
    expect(response).to have_http_status(:ok)
  end

  it "requires authentication before the feature gate" do
    set_feature_flag("journals", "off")

    get "/feature_gate_probe"

    expect(response).to have_http_status(:unauthorized)
  end

  it "answers 404, not 403, when a member reaches a role-gated endpoint of a Feature they cannot use" do
    set_feature_flag("journals", "preview")

    get "/feature_gate_probe/moderated", headers: auth_headers_for(create(:user, role_moderator: true))
    expect(response).to have_http_status(:not_found)

    set_feature_flag("journals", "live")

    get "/feature_gate_probe/moderated", headers: auth_headers_for(create(:user, role_member: true))
    expect(response).to have_http_status(:forbidden)
  end

  it "follows a flag change on the next request" do
    headers = auth_headers_for(create(:user, role_member: true))
    set_feature_flag("journals", "live")

    get "/feature_gate_probe", headers: headers
    expect(response).to have_http_status(:ok)

    set_feature_flag("journals", "off", by: "123")
    get "/feature_gate_probe", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  # The gate runs on every request to a Feature's endpoints, the bot's
  # included, so it reads the Feature Flags once per few seconds in a process
  # (one query for all of them), the caller's roles only when the answer
  # depends on them (Preview), and nothing for the bot's service token.
  describe "the gate's own reads" do
    include ActiveSupport::Testing::TimeHelpers

    # What the request reads besides authentication: "flags" (the
    # feature_flags table) and "roles" (the caller's role flags).
    def reads_of_gated_request(headers)
      reads = []
      callback = lambda do |*, payload|
        sql = payload[:sql]
        reads << "flags" if sql.include?('FROM "feature_flags"')
        reads << "roles" if sql.include?('"rpg_club_users"."role_admin"')
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/feature_gate_probe", headers: headers
      end
      reads
    end

    let(:headers) { auth_headers_for(create(:user, role_member: true)) }

    it "reads the Feature Flags in one query, and again only after a few seconds" do
      set_feature_flag("journals", "live")

      expect(reads_of_gated_request(headers)).to eq([ "flags" ])
      expect(reads_of_gated_request(headers)).to eq([])

      travel(Features::STATES_TTL + 1.second) do
        expect(reads_of_gated_request(headers)).to eq([ "flags" ])
      end
    end

    it "reads no roles for a Live or Off Feature" do
      %w[live off].each do |state|
        set_feature_flag("journals", state)

        expect(reads_of_gated_request(headers)).not_to include("roles"), state
      end
    end

    it "reads the caller's roles for a Preview Feature" do
      set_feature_flag("journals", "preview")

      expect(reads_of_gated_request(headers)).to eq([ "flags", "roles" ])
    end

    it "reads nothing for the bot's service token" do
      set_feature_flag("journals", "off")

      expect(reads_of_gated_request(service_headers)).to eq([])
    end
  end

  it "refuses to declare a Feature that is not registered" do
    expect { Class.new(ApplicationController) { feature :not_a_feature } }.to raise_error(KeyError)
  end
end
