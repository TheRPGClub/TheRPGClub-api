# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the thread <-> game link endpoints (#45): all actions are
# admin/service-gated, and every change recomputes the thread's derived
# `gamedb_game_id` (the MIN of its remaining links).
RSpec.describe "api/v1/thread_game_links behavior", type: :request do
  let(:thread) { create(:discord_thread) }
  let(:game_a) { create(:game) }
  let(:game_b) { create(:game) }

  describe "POST /api/v1/threads/:id/links" do
    it "links the thread to a game and recomputes the primary game" do
      expect {
        post "/api/v1/threads/#{thread.thread_id}/links",
          params: { data: { gamedb_game_id: game_a.game_id } }, headers: service_headers, as: :json
      }.to change(ThreadGameLink, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "thread_id" => thread.thread_id,
        "gamedb_game_id" => game_a.game_id
      )
      expect(json.dig("data", "linked_at")).to be_present
      expect(thread.reload.gamedb_game_id).to eq(game_a.game_id)
    end

    it "keeps the primary game at the MIN of the links" do
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { gamedb_game_id: game_b.game_id } }, headers: service_headers, as: :json
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { gamedb_game_id: game_a.game_id } }, headers: service_headers, as: :json

      expect(thread.reload.gamedb_game_id).to eq([ game_a.game_id, game_b.game_id ].min)
    end

    it "returns 200 for an existing link without duplicating it" do
      create(:thread_game_link, thread: thread, game: game_a)

      expect {
        post "/api/v1/threads/#{thread.thread_id}/links",
          params: { data: { gamedb_game_id: game_a.game_id } }, headers: service_headers, as: :json
      }.not_to change(ThreadGameLink, :count)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("gamedb_game_id" => game_a.game_id)
    end

    it "allows an admin" do
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { gamedb_game_id: game_a.game_id } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "422s for an unknown game" do
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { gamedb_game_id: 999_999_999 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "404s for an unknown thread" do
      post "/api/v1/threads/999999999999999999/links",
        params: { data: { gamedb_game_id: game_a.game_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when gamedb_game_id is missing" do
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { game: "not the right key" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/threads/#{thread.thread_id}/links",
          params: { data: { gamedb_game_id: game_a.game_id } },
          headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(ThreadGameLink, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/threads/#{thread.thread_id}/links",
        params: { data: { gamedb_game_id: game_a.game_id } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/threads/:id/links/:game_id" do
    it "removes one link and recomputes the primary game from the rest" do
      create(:thread_game_link, thread: thread, game: game_a)
      create(:thread_game_link, thread: thread, game: game_b)
      DiscordThread.recompute_primary_game!(thread.thread_id)
      lower, higher = [ game_a, game_b ].sort_by(&:game_id)

      delete "/api/v1/threads/#{thread.thread_id}/links/#{lower.game_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 1)
      expect(ThreadGameLink.where(thread_id: thread.thread_id).count).to eq(1)
      expect(thread.reload.gamedb_game_id).to eq(higher.game_id)
    end

    it "reports count 0 for a game that was not linked" do
      delete "/api/v1/threads/#{thread.thread_id}/links/#{game_a.game_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 0)
    end

    it "404s for an unknown thread" do
      delete "/api/v1/threads/999999999999999999/links/#{game_a.game_id}", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      create(:thread_game_link, thread: thread, game: game_a)

      delete "/api/v1/threads/#{thread.thread_id}/links/#{game_a.game_id}",
        headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(ThreadGameLink.where(thread_id: thread.thread_id).count).to eq(1)
    end
  end

  describe "DELETE /api/v1/threads/:id/links" do
    it "removes every link and clears the primary game" do
      create(:thread_game_link, thread: thread, game: game_a)
      create(:thread_game_link, thread: thread, game: game_b)
      DiscordThread.recompute_primary_game!(thread.thread_id)

      delete "/api/v1/threads/#{thread.thread_id}/links", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true, "count" => 2)
      expect(ThreadGameLink.where(thread_id: thread.thread_id)).to be_empty
      expect(thread.reload.gamedb_game_id).to be_nil
    end

    it "forbids a regular user" do
      create(:thread_game_link, thread: thread, game: game_a)

      delete "/api/v1/threads/#{thread.thread_id}/links", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(ThreadGameLink.where(thread_id: thread.thread_id).count).to eq(1)
    end

    it "requires authentication" do
      delete "/api/v1/threads/#{thread.thread_id}/links"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
