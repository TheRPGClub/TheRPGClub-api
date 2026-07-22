# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the GOTM entries endpoints: reads are open to any
# authenticated caller; create/update/destroy are admin/service-gated (#98).
RSpec.describe "api/v1/gotm_entries behavior", type: :request do
  describe "GET /api/v1/gotm_entries" do
    it "lists entries with all entry columns and pagination meta" do
      entry = create(:gotm_entry)

      get "/api/v1/gotm_entries", params: { round_number: entry.round_number },
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "gotm_id" => entry.gotm_id,
        "round_number" => entry.round_number,
        "month_year" => entry.month_year,
        "game_index" => entry.game_index,
        "gamedb_game_id" => entry.gamedb_game_id,
        "voting_results_message_id" => nil
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 1)
    end

    it "omits the game embed by default and includes it with include=game" do
      entry = create(:gotm_entry)

      get "/api/v1/gotm_entries", params: { round_number: entry.round_number }, headers: service_headers
      expect(json.fetch("data").first).not_to have_key("game")

      get "/api/v1/gotm_entries", params: { round_number: entry.round_number, include: "game" },
        headers: service_headers
      expect(json.dig("data", 0, "game")).to include(
        "game_id" => entry.gamedb_game_id,
        "title" => entry.game.title
      )
    end

    it "filters by round_number and orders the round's slots by game_index" do
      round = SecureRandom.random_number(1_000_000_000)
      second = create(:gotm_entry, round_number: round, game_index: 1)
      first = create(:gotm_entry, round_number: round, game_index: 0)
      create(:gotm_entry) # a different round, filtered out

      get "/api/v1/gotm_entries", params: { round_number: round }, headers: service_headers

      expect(json.fetch("data").map { |e| e.fetch("gotm_id") }).to eq([ first.gotm_id, second.gotm_id ])
    end

    it "requires authentication" do
      get "/api/v1/gotm_entries"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/gotm_entries/:id" do
    it "returns the entry to any authenticated user" do
      entry = create(:gotm_entry)

      get "/api/v1/gotm_entries/#{entry.gotm_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("gotm_id" => entry.gotm_id, "round_number" => entry.round_number)
      expect(json.fetch("data")).not_to have_key("game")
    end

    it "embeds the game with include=game" do
      entry = create(:gotm_entry)

      get "/api/v1/gotm_entries/#{entry.gotm_id}", params: { include: "game" }, headers: service_headers

      expect(json.dig("data", "game")).to include("game_id" => entry.gamedb_game_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/gotm_entries/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
      expect(json).to have_key("error")
    end
  end

  describe "POST /api/v1/gotm_entries" do
    let(:game) { create(:game) }
    let(:round) { SecureRandom.random_number(1_000_000_000) }
    let(:payload) do
      { data: { round_number: round, month_year: "Spec 2026", game_index: 0,
                gamedb_game_id: game.game_id, reddit_url: "https://reddit.example/r/spec" } }
    end

    it "creates an entry as the service" do
      expect {
        post "/api/v1/gotm_entries", params: payload, headers: service_headers, as: :json
      }.to change(GotmEntry.where(round_number: round), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "round_number" => round,
        "month_year" => "Spec 2026",
        "game_index" => 0,
        "gamedb_game_id" => game.game_id,
        "reddit_url" => "https://reddit.example/r/spec"
      )
    end

    it "allows an admin user" do
      post "/api/v1/gotm_entries", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/gotm_entries", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GotmEntry, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      post "/api/v1/gotm_entries", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "ignores the bot-managed voting_results_message_id on create" do
      post "/api/v1/gotm_entries",
        params: { data: payload[:data].merge(voting_results_message_id: "123456") },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "voting_results_message_id")).to be_nil
    end

    it "422s when a required field is missing" do
      post "/api/v1/gotm_entries",
        params: { data: payload[:data].except(:month_year) }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Month year")
    end

    it "422s for a duplicate round/game_index slot" do
      create(:gotm_entry, round_number: round, game_index: 0)

      expect {
        post "/api/v1/gotm_entries", params: payload, headers: service_headers, as: :json
      }.not_to change(GotmEntry, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/gotm_entries", params: { round_number: round }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/v1/gotm_entries/:id" do
    it "updates the mutable fields as the service" do
      entry = create(:gotm_entry)
      new_game = create(:game)

      patch "/api/v1/gotm_entries/#{entry.gotm_id}",
        params: { data: { reddit_url: "https://reddit.example/r/updated",
                          gamedb_game_id: new_game.game_id,
                          voting_results_message_id: "9876" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "reddit_url" => "https://reddit.example/r/updated",
        "gamedb_game_id" => new_game.game_id,
        "voting_results_message_id" => "9876"
      )
      expect(entry.reload.voting_results_message_id).to eq("9876")
    end

    it "leaves the round identity fixed (round_number/game_index are not updatable)" do
      entry = create(:gotm_entry, game_index: 0)

      patch "/api/v1/gotm_entries/#{entry.gotm_id}",
        params: { data: { round_number: entry.round_number + 1, game_index: 5 } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.game_index).to eq(0)
      expect(json.dig("data", "game_index")).to eq(0)
    end

    it "forbids a regular user" do
      entry = create(:gotm_entry)

      patch "/api/v1/gotm_entries/#{entry.gotm_id}",
        params: { data: { reddit_url: "https://hijack.example" } },
        headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.reddit_url).not_to eq("https://hijack.example")
    end

    it "404s for an unknown id" do
      patch "/api/v1/gotm_entries/999999999",
        params: { data: { reddit_url: "https://x.example" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/gotm_entries/:id" do
    it "deletes the entry as an admin" do
      entry = create(:gotm_entry)

      delete "/api/v1/gotm_entries/#{entry.gotm_id}", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GotmEntry.exists?(entry.gotm_id)).to be(false)
    end

    it "forbids a regular user" do
      entry = create(:gotm_entry)

      delete "/api/v1/gotm_entries/#{entry.gotm_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GotmEntry.exists?(entry.gotm_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/gotm_entries/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
