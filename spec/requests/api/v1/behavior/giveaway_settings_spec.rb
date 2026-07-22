# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the donor giveaway-settings document (#95): GET is open
# and defaults to false for unknown users; PATCH is owner-only (service may
# act on anyone's behalf) and upserts the user row.
RSpec.describe "api/v1/giveaway_settings behavior", type: :request do
  let(:owner) { create(:user) }

  describe "GET /api/v1/users/:user_id/giveaway_settings" do
    it "returns the stored preference to any authenticated caller" do
      owner.update!(donor_notify_on_claim: true)

      get "/api/v1/users/#{owner.user_id}/giveaway_settings", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => owner.user_id, "notify_on_claim" => true)
    end

    it "defaults to false for an unknown user" do
      get "/api/v1/users/999999999999999999/giveaway_settings", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => "999999999999999999", "notify_on_claim" => false)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/giveaway_settings"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/users/:user_id/giveaway_settings" do
    it "updates the owner's preference" do
      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { data: { notify_on_claim: true } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => owner.user_id, "notify_on_claim" => true)
      expect(owner.reload.donor_notify_on_claim).to be(true)
    end

    it "casts string booleans" do
      owner.update!(donor_notify_on_claim: true)

      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { data: { notify_on_claim: "false" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => owner.user_id, "notify_on_claim" => false)
      expect(owner.reload.donor_notify_on_claim).to be(false)
    end

    it "allows the service and creates a missing user row (upsert)" do
      fresh_id = SecureRandom.random_number(10**18).to_s

      expect {
        patch "/api/v1/users/#{fresh_id}/giveaway_settings",
          params: { data: { notify_on_claim: true } }, headers: service_headers, as: :json
      }.to change(RpgClubUser.where(user_id: fresh_id), :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("user_id" => fresh_id, "notify_on_claim" => true)
      expect(RpgClubUser.find(fresh_id).donor_notify_on_claim).to be(true)
    end

    it "forbids another user" do
      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { data: { notify_on_claim: true } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(owner.reload.donor_notify_on_claim).to be(false)
    end

    it "422s when notify_on_claim is missing" do
      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { data: { something_else: true } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("error" => "notify_on_claim required")
    end

    it "400s when the data envelope is missing" do
      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { notify_on_claim: true }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      patch "/api/v1/users/#{owner.user_id}/giveaway_settings",
        params: { data: { notify_on_claim: true } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
