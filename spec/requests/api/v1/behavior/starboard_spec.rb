# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the starboard endpoints: full CRUD keyed on the Discord
# message id (a client-supplied string snowflake PK), open to any
# authenticated caller.
RSpec.describe "api/v1/starboard behavior", type: :request do
  describe "GET /api/v1/starboard" do
    it "lists entries newest first with the documented fields" do
      older = create(:starboard_entry, created_at: 2.days.ago)
      newer = create(:starboard_entry, created_at: 1.day.ago)

      get "/api/v1/starboard", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |e| e.fetch("message_id") }
      expect(ids.index(newer.message_id)).to be < ids.index(older.message_id)
      body = json.fetch("data").find { |e| e["message_id"] == newer.message_id }
      expect(body).to include(
        "message_id" => newer.message_id,
        "channel_id" => newer.channel_id,
        "starboard_message_id" => newer.starboard_message_id,
        "author_id" => newer.author_id,
        "star_count" => newer.star_count
      )
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "requires authentication" do
      get "/api/v1/starboard"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/starboard/:message_id" do
    it "returns the entry" do
      entry = create(:starboard_entry)

      get "/api/v1/starboard/#{entry.message_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "message_id" => entry.message_id,
        "star_count" => entry.star_count
      )
    end

    it "404s for an unknown message id" do
      get "/api/v1/starboard/999999999999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/starboard" do
    let(:message_id) { SecureRandom.random_number(10**18).to_s }
    let(:payload) do
      { data: { message_id: message_id, channel_id: "111", starboard_message_id: "222",
        author_id: "333", star_count: 5 } }
    end

    it "creates an entry as the service" do
      expect {
        post "/api/v1/starboard", params: payload, headers: service_headers, as: :json
      }.to change(RpgClubStarboardEntry, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "message_id" => message_id,
        "channel_id" => "111",
        "starboard_message_id" => "222",
        "author_id" => "333",
        "star_count" => 5
      )
    end

    it "allows any authenticated caller and defaults star_count to 0" do
      post "/api/v1/starboard",
        params: { data: payload[:data].except(:star_count) },
        headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "star_count")).to eq(0)
    end

    it "422s on a duplicate message_id" do
      existing = create(:starboard_entry)

      expect {
        post "/api/v1/starboard",
          params: { data: payload[:data].merge(message_id: existing.message_id) },
          headers: service_headers, as: :json
      }.not_to change(RpgClubStarboardEntry, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("duplicate")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/starboard", params: { message_id: message_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/starboard", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/starboard/:message_id" do
    it "updates the star count" do
      entry = create(:starboard_entry, star_count: 1)

      patch "/api/v1/starboard/#{entry.message_id}",
        params: { data: { star_count: 9 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("message_id" => entry.message_id, "star_count" => 9)
      expect(entry.reload.star_count).to eq(9)
    end

    it "supports PUT as an alias" do
      entry = create(:starboard_entry, star_count: 1)

      put "/api/v1/starboard/#{entry.message_id}",
        params: { data: { star_count: 4 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.star_count).to eq(4)
    end

    it "404s for an unknown message id" do
      patch "/api/v1/starboard/999999999999999999",
        params: { data: { star_count: 2 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/starboard/:message_id" do
    it "deletes the entry" do
      entry = create(:starboard_entry)

      delete "/api/v1/starboard/#{entry.message_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubStarboardEntry.exists?(entry.message_id)).to be(false)
    end

    it "404s for an unknown message id" do
      delete "/api/v1/starboard/999999999999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
