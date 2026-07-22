# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the user backlog endpoints: reads are open to any
# authenticated principal, writes are gated to the owner (or the service).
RSpec.describe "api/v1/backlog behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/backlog" do
    it "lists only that user's entries with the embedded game" do
      entry = create(:backlog_entry, user: owner)
      create(:backlog_entry, user: other_user)

      get "/api/v1/users/#{owner.user_id}/backlog", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "entry_id" => entry.entry_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => entry.gamedb_game_id
      )
      expect(json.dig("data", 0, "game")).to include("game_id" => entry.gamedb_game_id)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/backlog"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/backlog" do
    let(:game) { create(:game) }
    let(:payload) { { data: { gamedb_game_id: game.game_id, note: "next up" } } }

    it "creates an entry for the owner" do
      expect {
        post "/api/v1/users/#{owner.user_id}/backlog",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameBacklog.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "note" => "next up"
      )
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/backlog", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/backlog",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameBacklog, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/backlog",
        params: { data: { gamedb_game_id: 999_999_999 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /api/v1/backlog/:id" do
    it "shows an entry to any authenticated user" do
      entry = create(:backlog_entry, user: owner)

      get "/api/v1/backlog/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("entry_id" => entry.entry_id)
    end

    it "404s for an unknown id" do
      get "/api/v1/backlog/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/backlog/:id" do
    it "updates the owner's entry" do
      entry = create(:backlog_entry, user: owner)

      patch "/api/v1/backlog/#{entry.entry_id}",
        params: { data: { note: "updated note" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "note")).to eq("updated note")
      expect(entry.reload.note).to eq("updated note")
    end

    it "forbids a non-owner" do
      entry = create(:backlog_entry, user: owner)

      patch "/api/v1/backlog/#{entry.entry_id}",
        params: { data: { note: "hijacked" } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(entry.reload.note).not_to eq("hijacked")
    end
  end

  describe "DELETE /api/v1/backlog/:id" do
    it "deletes the owner's entry" do
      entry = create(:backlog_entry, user: owner)

      delete "/api/v1/backlog/#{entry.entry_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameBacklog.exists?(entry.entry_id)).to be(false)
    end

    it "forbids a non-owner" do
      entry = create(:backlog_entry, user: owner)

      delete "/api/v1/backlog/#{entry.entry_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameBacklog.exists?(entry.entry_id)).to be(true)
    end
  end
end
