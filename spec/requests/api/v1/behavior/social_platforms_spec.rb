# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the social-platforms catalog: the position/label-ordered
# list and the open-to-any-authenticated-caller create with its
# duplicate-label upsert (200 with the existing record).
RSpec.describe "api/v1/social_platforms behavior", type: :request do
  describe "GET /api/v1/social_platforms" do
    it "lists platforms ordered by position" do
      late = create(:social_platform, label: "ordsp bb #{SecureRandom.hex(4)}", position: 20)
      early = create(:social_platform, label: "ordsp aa #{SecureRandom.hex(4)}", position: 10)

      get "/api/v1/social_platforms", params: { per: 500 }, headers: service_headers

      expect(response).to have_http_status(:ok)
      labels = json.fetch("data").map { |p| p.fetch("label") }
      expect(labels.index(early.label)).to be < labels.index(late.label)
    end

    it "tie-breaks equal positions by label" do
      zz = create(:social_platform, label: "ordsp zz #{SecureRandom.hex(4)}", position: 30)
      aa = create(:social_platform, label: "ordsp aa #{SecureRandom.hex(4)}", position: 30)

      get "/api/v1/social_platforms", params: { per: 500 }, headers: service_headers

      labels = json.fetch("data").map { |p| p.fetch("label") }
      expect(labels.index(aa.label)).to be < labels.index(zz.label)
    end

    it "serializes the documented fields with pagination meta" do
      platform = create(:social_platform, position: 7)

      get "/api/v1/social_platforms", params: { per: 500 }, headers: auth_headers_for(create(:user))

      row = json.fetch("data").find { |p| p["id"] == platform.id }
      expect(row).to include("label" => platform.label, "position" => 7)
      expect(row).to have_key("created_by_user_id")
      expect(row).to have_key("created_at")
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "requires authentication" do
      get "/api/v1/social_platforms"

      expect(response).to have_http_status(:unauthorized)
      expect(json).to eq("error" => "unauthorized")
    end
  end

  describe "POST /api/v1/social_platforms" do
    it "creates a platform for a regular user, stamping created_by_user_id from the caller" do
      user = create(:user)
      label = "Bluesky #{SecureRandom.hex(4)}"

      expect {
        post "/api/v1/social_platforms", params: { data: { label: label, position: 5 } },
          headers: auth_headers_for(user), as: :json
      }.to change(SocialPlatform, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "label" => label,
        "position" => 5,
        "created_by_user_id" => user.user_id
      )
    end

    it "defaults position to 1000 when omitted" do
      label = "Twitch #{SecureRandom.hex(4)}"

      post "/api/v1/social_platforms", params: { data: { label: label } },
        headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "position")).to eq(1000)
    end

    it "ignores a client-sent created_by_user_id in favor of the caller" do
      user = create(:user)
      label = "Cohost #{SecureRandom.hex(4)}"

      post "/api/v1/social_platforms",
        params: { data: { label: label, created_by_user_id: "someone-else" } },
        headers: auth_headers_for(user), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "created_by_user_id")).to eq(user.user_id)
    end

    it "creates as the service principal" do
      label = "Steam #{SecureRandom.hex(4)}"

      post "/api/v1/social_platforms", params: { data: { label: label } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "created_by_user_id")).to eq("discord_bot")
    end

    it "returns the existing platform with 200 on a duplicate label, case-insensitively" do
      existing = create(:social_platform, label: "Mastodon #{SecureRandom.hex(4)}")

      expect {
        post "/api/v1/social_platforms", params: { data: { label: existing.label.upcase } },
          headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(SocialPlatform, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => existing.id, "label" => existing.label)
    end

    it "422s when label is blank" do
      post "/api/v1/social_platforms", params: { data: { label: "   " } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Label")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/social_platforms", params: { label: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/social_platforms", params: { data: { label: "Nope" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
