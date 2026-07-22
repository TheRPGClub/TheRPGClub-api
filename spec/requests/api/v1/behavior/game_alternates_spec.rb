# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the alternate-version link endpoint
# (POST /api/v1/games/:id/alternates): symmetric low-id-first storage,
# idempotency, and the admin/service gate.
RSpec.describe "api/v1/game_alternates behavior", type: :request do
  # Eager (let!) so game_low is always created first and holds the lower
  # game_id — the pair-ordering assertions depend on it.
  let!(:game_low) { create(:game) }
  let!(:game_high) { create(:game) }

  describe "POST /api/v1/games/:id/alternates" do
    it "links the pair low id first regardless of which game the request hangs off" do
      expect {
        post "/api/v1/games/#{game_high.game_id}/alternates",
          params: { data: { alt_game_id: game_low.game_id } }, headers: service_headers, as: :json
      }.to change(GamedbGameAlternate, :count).by(1)

      expect(response).to have_http_status(:created)
      link = GamedbGameAlternate.find_by!(game_id: game_low.game_id, alt_game_id: game_high.game_id)
      expect(link.created_by).to eq("discord_bot")
      expect(json.fetch("data").map { |g| g.fetch("game_id") }).to eq([ game_low.game_id ])
    end

    it "returns the game's full alternates list in the GameResource shape" do
      post "/api/v1/games/#{game_low.game_id}/alternates",
        params: { data: { alt_game_id: game_high.game_id } }, headers: service_headers, as: :json

      expect(json.fetch("data").first).to include(
        "game_id" => game_high.game_id,
        "title" => game_high.title,
        "gotm_won" => false,
        "nr_gotm_won" => false
      )
    end

    it "touches both games so their cached relations invalidate" do
      expect {
        post "/api/v1/games/#{game_low.game_id}/alternates",
          params: { data: { alt_game_id: game_high.game_id } }, headers: service_headers, as: :json
      }.to change { game_low.reload.updated_at }
        .and change { game_high.reload.updated_at }
    end

    it "records the acting admin in created_by" do
      admin = create(:user, :admin)

      post "/api/v1/games/#{game_low.game_id}/alternates",
        params: { data: { alt_game_id: game_high.game_id } }, headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:created)
      link = GamedbGameAlternate.find_by!(game_id: game_low.game_id, alt_game_id: game_high.game_id)
      expect(link.created_by).to eq(admin.user_id)
    end

    it "is idempotent: re-linking from either side returns 200 without a new row" do
      GamedbGameAlternate.create!(game_id: game_low.game_id, alt_game_id: game_high.game_id)

      expect {
        post "/api/v1/games/#{game_low.game_id}/alternates",
          params: { data: { alt_game_id: game_high.game_id } }, headers: service_headers, as: :json
      }.not_to change(GamedbGameAlternate, :count)
      expect(response).to have_http_status(:ok)

      expect {
        post "/api/v1/games/#{game_high.game_id}/alternates",
          params: { data: { alt_game_id: game_low.game_id } }, headers: service_headers, as: :json
      }.not_to change(GamedbGameAlternate, :count)
      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |g| g.fetch("game_id") }).to eq([ game_low.game_id ])
    end

    it "422s when a game is linked to itself" do
      expect {
        post "/api/v1/games/#{game_low.game_id}/alternates",
          params: { data: { alt_game_id: game_low.game_id } }, headers: service_headers, as: :json
      }.not_to change(GamedbGameAlternate, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("a game cannot be its own alternate")
    end

    it "404s for an unknown path game" do
      post "/api/v1/games/999999999/alternates",
        params: { data: { alt_game_id: game_low.game_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "404s for an unknown alt_game_id without inserting a dangling link" do
      expect {
        post "/api/v1/games/#{game_low.game_id}/alternates",
          params: { data: { alt_game_id: 999_999_999 } }, headers: service_headers, as: :json
      }.not_to change(GamedbGameAlternate, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/games/#{game_low.game_id}/alternates",
        params: { alt_game_id: game_high.game_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "400s when alt_game_id is not an integer" do
      post "/api/v1/games/#{game_low.game_id}/alternates",
        params: { data: { alt_game_id: "abc" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games/#{game_low.game_id}/alternates",
          params: { data: { alt_game_id: game_high.game_id } },
          headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbGameAlternate, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      post "/api/v1/games/#{game_low.game_id}/alternates",
        params: { data: { alt_game_id: game_high.game_id } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
