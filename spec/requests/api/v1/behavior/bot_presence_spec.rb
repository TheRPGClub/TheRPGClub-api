# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the bot presence history endpoints (#94): every action is
# service-only (the bot's bearer token), and `id`/`set_at` are server-managed.
RSpec.describe "api/v1/bot_presence behavior", type: :request do
  describe "GET /api/v1/bot_presence" do
    it "lists entries newest first without the surrogate id" do
      BotPresenceHistory.delete_all
      older = create(:bot_presence_entry, set_at: 2.hours.ago)
      newer = create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence", headers: service_headers

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |e| e.fetch("activity_name") }
      expect(names).to eq([ newer.activity_name, older.activity_name ])
      expect(json.fetch("data").first).to include(
        "activity_name" => newer.activity_name,
        "set_by_user_id" => nil,
        "set_by_username" => nil
      )
      expect(json.fetch("data").first).not_to have_key("id")
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "caps the page size at 50 even when more is requested" do
      create(:bot_presence_entry)

      get "/api/v1/bot_presence", params: { per: 100 }, headers: service_headers

      expect(json.dig("meta", "per")).to eq(50)
    end

    it "supports the bot's limit alias" do
      BotPresenceHistory.delete_all
      create(:bot_presence_entry, set_at: 2.hours.ago)
      create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence", params: { limit: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 1, "pages" => 2)
    end

    it "forbids a regular user" do
      get "/api/v1/bot_presence", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids even an admin (service-only)" do
      get "/api/v1/bot_presence", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      get "/api/v1/bot_presence"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/bot_presence/latest" do
    it "returns the most recent entry" do
      BotPresenceHistory.delete_all
      create(:bot_presence_entry, set_at: 2.hours.ago)
      newest = create(:bot_presence_entry, set_at: 1.hour.ago)

      get "/api/v1/bot_presence/latest", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("activity_name" => newest.activity_name)
    end

    it "returns null when no entries exist" do
      BotPresenceHistory.delete_all

      get "/api/v1/bot_presence/latest", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => nil)
    end

    it "forbids a regular user" do
      get "/api/v1/bot_presence/latest", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get "/api/v1/bot_presence/latest"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/bot_presence" do
    let(:payload) { { data: { activity_name: "Golden Sun", set_by_user_id: "42", set_by_username: "iso" } } }

    it "records an entry with a server-stamped set_at" do
      expect {
        post "/api/v1/bot_presence", params: payload, headers: service_headers, as: :json
      }.to change(BotPresenceHistory, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "activity_name" => "Golden Sun",
        "set_by_user_id" => "42",
        "set_by_username" => "iso"
      )
      expect(json.dig("data", "set_at")).to be_present
    end

    it "ignores client-sent id and set_at (server-managed)" do
      post "/api/v1/bot_presence",
        params: { data: { activity_name: "Stamped", id: 424_242, set_at: "2000-01-01T00:00:00Z" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      record = BotPresenceHistory.find_by!(activity_name: "Stamped")
      expect(record.id).not_to eq(424_242)
      expect(record.set_at).to be > 1.day.ago
    end

    it "422s when activity_name exceeds the column limit" do
      post "/api/v1/bot_presence",
        params: { data: { activity_name: "x" * 2000 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/bot_presence", params: { activity_name: "Bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/bot_presence", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(BotPresenceHistory, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/bot_presence", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
