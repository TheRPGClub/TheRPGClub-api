# frozen_string_literal: true

require "rails_helper"

# Behavior specs for PUT /api/v1/users/:user_id/roles, the service-only role
# report the bot sends on a guild member update, and for role IDs carried on
# the member upsert. Both replace the Superadmin (dev), Admin, Moderator,
# Regulars and Members flags with the ones the reported Discord roles grant
# (the stored dev role is covered by behavior/feature_access_spec.rb).
RSpec.describe "api/v1/users/:user_id/roles behavior", type: :request do
  let(:admin_role) { "461891227613265940" }
  let(:moderator_role) { "267881447258325002" }
  let(:regulars_role) { "267883288817958912" }
  let(:members_role) { "747520789003239530" }

  def report_roles(user_id, role_ids, headers: service_headers)
    put "/api/v1/users/#{user_id}/roles", params: { data: { role_ids: role_ids } }, headers: headers, as: :json
  end

  def session_membership(user)
    get "/api/v1/session", headers: auth_headers_for(user)
    json.fetch("membership")
  end

  describe "PUT /api/v1/users/:user_id/roles" do
    it "sets the flags the reported roles grant and returns the refreshed membership" do
      user = create(:user)

      report_roles(user.user_id, [ admin_role, moderator_role, regulars_role, members_role, "42" ])

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq(
        "user_id" => user.user_id,
        "membership" => {
          "admin" => true, "moderator" => true, "regular" => true,
          "member" => true, "newcomer" => false, "active" => true
        }
      )
    end

    it "lets a gained staff role show in the member's existing session straight away" do
      user = create(:user)
      headers = auth_headers_for(user)

      report_roles(user.user_id, [ moderator_role ])
      get "/api/v1/session", headers: headers

      expect(json.fetch("membership")).to include("moderator" => true, "admin" => false)
    end

    it "clears the flags of roles the member no longer holds" do
      user = create(:user, :admin, role_moderator: true, role_regular: true, role_member: true)

      report_roles(user.user_id, [ regulars_role ])

      expect(session_membership(user)).to include(
        "admin" => false, "moderator" => false, "regular" => true, "member" => false
      )
    end

    it "clears every role flag for an empty role list" do
      user = create(:user, :admin, role_member: true)

      report_roles(user.user_id, [])

      expect(response).to have_http_status(:ok)
      expect(session_membership(user)).to include("admin" => false, "member" => false)
    end

    it "422s when role_ids is not a list" do
      user = create(:user, :admin)

      report_roles(user.user_id, admin_role)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("role_ids")
      expect(session_membership(user)).to include("admin" => true)
    end

    it "422s when role_ids is missing" do
      user = create(:user)

      put "/api/v1/users/#{user.user_id}/roles", params: { data: { roles: [] } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for an unknown member" do
      report_roles("999999999999999999", [ members_role ])

      expect(response).to have_http_status(:not_found)
    end

    it "forbids user tokens, including admins and Superadmins" do
      user = create(:user)
      admin = create(:user, :admin)

      report_roles(user.user_id, [ admin_role ], headers: auth_headers_for(admin))
      expect(response).to have_http_status(:forbidden)

      report_roles(user.user_id, [ admin_role ], headers: auth_headers_for(user, is_dev: true))
      expect(response).to have_http_status(:forbidden)

      expect(session_membership(user)).to include("admin" => false)
    end

    it "requires authentication" do
      user = create(:user)

      report_roles(user.user_id, [ admin_role ], headers: {})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/upsert with role_ids" do
    it "sets the role flags on a new member" do
      discord_id = SecureRandom.random_number(10**18).to_s

      post "/api/v1/users/upsert", params: { data: { discord_id: discord_id, role_ids: [ members_role ] } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(session_membership(RpgClubUser.find(discord_id))).to include("member" => true, "admin" => false)
    end

    it "replaces the role flags on an existing member" do
      user = create(:user, :admin)

      post "/api/v1/users/upsert", params: { data: { discord_id: user.user_id, role_ids: [ regulars_role ] } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(session_membership(user)).to include("admin" => false, "regular" => true)
    end

    it "leaves the role flags alone when role_ids is omitted" do
      user = create(:user, :admin)

      post "/api/v1/users/upsert", params: { data: { discord_id: user.user_id, username: "renamed" } },
        headers: service_headers, as: :json

      expect(session_membership(user)).to include("admin" => true)
    end

    it "422s when role_ids is not a list" do
      user = create(:user, :admin)

      post "/api/v1/users/upsert", params: { data: { discord_id: user.user_id, role_ids: admin_role } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(session_membership(user)).to include("admin" => true)
    end
  end
end
