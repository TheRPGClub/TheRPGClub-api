# frozen_string_literal: true

require "rails_helper"

# Behavior specs for user social links: reads are open to any authenticated
# principal, writes are gated to the owner (or the service). Each row embeds
# its social_platform.
RSpec.describe "api/v1/user_socials behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:platform) { SocialPlatform.create!(label: "Social #{SecureRandom.hex(6)}") }

  describe "GET /api/v1/users/:user_id/socials" do
    it "lists only that user's socials with the embedded platform, id ascending" do
      first = create(:user_social, user: owner)
      second = create(:user_social, user: owner)
      create(:user_social, user: other_user)

      get "/api/v1/users/#{owner.user_id}/socials", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |s| s.fetch("id") }).to eq([ first.id, second.id ])
      expect(json.fetch("data").first).to include(
        "id" => first.id,
        "user_id" => owner.user_id,
        "platform_id" => first.platform_id,
        "url" => first.url,
        "display_text" => first.display_text
      )
      expect(json.dig("data", 0, "social_platform")).to include(
        "id" => first.platform_id,
        "label" => first.social_platform.label
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/socials"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/socials" do
    let(:payload) do
      { data: { platform_id: platform.id, url: "https://example.test/#{SecureRandom.hex(6)}",
                display_text: "My Profile" } }
    end

    it "creates a link for the owner with the embedded platform" do
      expect {
        post "/api/v1/users/#{owner.user_id}/socials",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserSocial.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "platform_id" => platform.id,
        "url" => payload.dig(:data, :url),
        "display_text" => "My Profile"
      )
      expect(json.dig("data", "social_platform")).to include("label" => platform.label)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/socials", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user, even an admin" do
      expect {
        post "/api/v1/users/#{owner.user_id}/socials",
          params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json
      }.not_to change(UserSocial, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "422s for an unknown platform_id" do
      post "/api/v1/users/#{owner.user_id}/socials",
        params: { data: { platform_id: 999_999_999 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for a duplicate url on the same (user, platform)" do
      existing = create(:user_social, user: owner, social_platform: platform)

      expect {
        post "/api/v1/users/#{owner.user_id}/socials",
          params: { data: { platform_id: platform.id, url: existing.url } },
          headers: auth_headers_for(owner), as: :json
      }.not_to change(UserSocial, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown attribute name in data" do
      post "/api/v1/users/#{owner.user_id}/socials",
        params: { data: { platform_id: platform.id, handle: "not-a-column" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/socials",
        params: { platform_id: platform.id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/socials", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/user_socials/:id" do
    it "shows a link to any authenticated user" do
      social = create(:user_social, user: owner)

      get "/api/v1/user_socials/#{social.id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("id" => social.id, "url" => social.url)
      expect(json.dig("data", "social_platform")).to include("id" => social.platform_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/user_socials/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end

    it "requires authentication" do
      social = create(:user_social, user: owner)

      get "/api/v1/user_socials/#{social.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/user_socials/:id" do
    it "updates the owner's link" do
      social = create(:user_social, user: owner)

      patch "/api/v1/user_socials/#{social.id}",
        params: { data: { display_text: "Updated Label" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "display_text")).to eq("Updated Label")
      expect(social.reload.display_text).to eq("Updated Label")
    end

    it "allows the service" do
      social = create(:user_social, user: owner)

      patch "/api/v1/user_socials/#{social.id}",
        params: { data: { url: "https://example.test/svc-#{SecureRandom.hex(4)}" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "forbids a non-owner" do
      social = create(:user_social, user: owner)

      patch "/api/v1/user_socials/#{social.id}",
        params: { data: { display_text: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(social.reload.display_text).not_to eq("hijacked")
    end

    it "422s for a duplicate url on the same (user, platform)" do
      kept = create(:user_social, user: owner, social_platform: platform)
      social = create(:user_social, user: owner, social_platform: platform)

      patch "/api/v1/user_socials/#{social.id}",
        params: { data: { url: kept.url } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(social.reload.url).not_to eq(kept.url)
    end

    it "404s for an unknown id as the service" do
      patch "/api/v1/user_socials/999999999",
        params: { data: { display_text: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      social = create(:user_social, user: owner)

      patch "/api/v1/user_socials/#{social.id}", params: { data: { display_text: "x" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/user_socials/:id" do
    it "deletes the owner's link" do
      social = create(:user_social, user: owner)

      delete "/api/v1/user_socials/#{social.id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserSocial.exists?(social.id)).to be(false)
    end

    it "allows the service" do
      social = create(:user_social, user: owner)

      delete "/api/v1/user_socials/#{social.id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(UserSocial.exists?(social.id)).to be(false)
    end

    it "forbids a non-owner" do
      social = create(:user_social, user: owner)

      delete "/api/v1/user_socials/#{social.id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserSocial.exists?(social.id)).to be(true)
    end

    it "404s for an unknown id as the service" do
      delete "/api/v1/user_socials/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      social = create(:user_social, user: owner)

      delete "/api/v1/user_socials/#{social.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
