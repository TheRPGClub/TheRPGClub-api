# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the favorites endpoints: reads are open to any
# authenticated principal, writes are gated to the owner (or the service).
RSpec.describe "api/v1/favorites behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/favorites" do
    it "lists only that user's favorites with the embedded game, ordered by sort_order" do
      second = create(:favorite, user: owner, sort_order: 2)
      first = create(:favorite, user: owner, sort_order: 1, note: "all-time great")
      create(:favorite, user: other_user)

      get "/api/v1/users/#{owner.user_id}/favorites", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |f| f.fetch("entry_id") }).to eq([ first.entry_id, second.entry_id ])
      expect(json.fetch("data").first).to include(
        "entry_id" => first.entry_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => first.gamedb_game_id,
        "note" => "all-time great"
      )
      expect(json.dig("data", 0, "game")).to include("game_id" => first.gamedb_game_id)
    end

    it "does not expose the dropped bookkeeping columns" do
      create(:favorite, user: owner, sort_order: 1)

      get "/api/v1/users/#{owner.user_id}/favorites", headers: service_headers

      entry = json.fetch("data").first
      expect(entry).not_to have_key("sort_order")
      expect(entry).not_to have_key("created_at")
      expect(entry).not_to have_key("updated_at")
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/favorites"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/favorites" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, note: "desert island pick" } } }

    it "creates a favorite for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/favorites",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameFavorite.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "note" => "desert island pick"
      )
      expect(json.dig("data", "game", "game_id")).to eq(game.game_id)
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/favorites", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/favorites",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameFavorite, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s when the game is already favorited (unique per user and game)" do
      create(:favorite, user: owner, game: game)

      expect {
        post "/api/v1/users/#{owner.user_id}/favorites",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(UserGameFavorite, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/favorites",
        params: { data: { gamedb_game_id: 999_999_999 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/favorites",
        params: { gamedb_game_id: game.game_id }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/favorites", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/favorites/:id" do
    it "shows a favorite to any authenticated user" do
      favorite = create(:favorite, user: owner)

      get "/api/v1/favorites/#{favorite.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("entry_id" => favorite.entry_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/favorites/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/favorites/:id" do
    it "updates the owner's favorite" do
      favorite = create(:favorite, user: owner)

      patch "/api/v1/favorites/#{favorite.entry_id}",
        params: { data: { note: "updated note" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "note")).to eq("updated note")
      expect(favorite.reload.note).to eq("updated note")
    end

    it "allows the service" do
      favorite = create(:favorite, user: owner)

      patch "/api/v1/favorites/#{favorite.entry_id}",
        params: { data: { note: "service note" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(favorite.reload.note).to eq("service note")
    end

    it "forbids a non-owner" do
      favorite = create(:favorite, user: owner)

      patch "/api/v1/favorites/#{favorite.entry_id}",
        params: { data: { note: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(favorite.reload.note).not_to eq("hijacked")
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/favorites/999999999",
        params: { data: { note: "x" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/favorites/:id" do
    it "deletes the owner's favorite" do
      favorite = create(:favorite, user: owner)

      delete "/api/v1/favorites/#{favorite.entry_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameFavorite.exists?(favorite.entry_id)).to be(false)
    end

    it "forbids a non-owner" do
      favorite = create(:favorite, user: owner)

      delete "/api/v1/favorites/#{favorite.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameFavorite.exists?(favorite.entry_id)).to be(true)
    end
  end
end
