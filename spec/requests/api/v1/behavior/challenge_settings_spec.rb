# frozen_string_literal: true

require "rails_helper"

# The member's Challenge DM opt-out (spec #376, ticket #379): whether the
# lifecycle job may send them Challenge reminder DMs. On until they turn it
# off; only the member (or the bot acting for them) reads and changes it.
RSpec.describe "api/v1/challenge_settings behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  def settings_path(user_id = member.user_id) = "/api/v1/users/#{user_id}/challenge_settings"

  describe "GET /api/v1/users/:user_id/challenge_settings" do
    it "shows a member that Challenge DMs are on until they turn them off" do
      get settings_path, headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => member.user_id, "dms" => true)
    end

    it "lets the bot read any member's, on for a member it has never seen" do
      get settings_path("999999999999999999"), headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => "999999999999999999", "dms" => true)
    end

    it "is the member's own" do
      get settings_path, headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/users/:user_id/challenge_settings" do
    def change(dms, as: member, user_id: member.user_id)
      patch settings_path(user_id), params: { data: { dms: dms } }, headers: as, as: :json
    end

    it "turns the member's Challenge DMs off and on again" do
      change(false, as: auth_headers_for(member))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => member.user_id, "dms" => false)
      get settings_path, headers: auth_headers_for(member)
      expect(json.dig("data", "dms")).to be(false)

      change("true", as: auth_headers_for(member))
      expect(json.fetch("data")).to eq("user_id" => member.user_id, "dms" => true)
    end

    it "lets the bot change it for a member, creating their record" do
      fresh_id = SecureRandom.random_number(10**18).to_s

      change(false, as: service_headers, user_id: fresh_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => fresh_id, "dms" => false)
    end

    it "refuses another member" do
      change(false, as: auth_headers_for(create(:user)))

      expect(response).to have_http_status(:forbidden)
      get settings_path, headers: auth_headers_for(member)
      expect(json.dig("data", "dms")).to be(true)
    end

    it "needs dms" do
      patch settings_path, params: { data: { other: true } }, headers: auth_headers_for(member), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "invalid_settings", "message" => "dms must be true or false")
    end

    it "is unavailable while Challenges is Off" do
      set_feature_flag("challenges", "off")

      change(false, as: auth_headers_for(member))

      expect(response).to have_http_status(:not_found)
    end
  end
end
