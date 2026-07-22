# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the Discord threads endpoints (#45): reads are open to
# any authenticated caller; the upsert and update are admin/service-gated. The
# derived `gamedb_game_id` is never client-writable, and the upsert refreshes
# only SYNC_COLUMNS on an existing row.
RSpec.describe "api/v1/threads behavior", type: :request do
  let(:game) { create(:game) }

  describe "GET /api/v1/games/:id/threads" do
    it "lists the threads linked to the game, newest first" do
      older = create(:discord_thread, created_at: 2.days.ago)
      newer = create(:discord_thread, created_at: 1.day.ago)
      create(:thread_game_link, thread: older, game: game)
      create(:thread_game_link, thread: newer, game: game)
      create(:thread_game_link)

      get "/api/v1/games/#{game.game_id}/threads", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      ids = json.fetch("data").map { |t| t.fetch("thread_id") }
      expect(ids).to eq([ newer.thread_id, older.thread_id ])
      expect(json.fetch("data").first).to include(
        "thread_id" => newer.thread_id,
        "thread_name" => newer.thread_name,
        "forum_channel_id" => newer.forum_channel_id,
        "is_archived" => "N",
        "skip_linking" => "N"
      )
      expect(json.fetch("data").first).to have_key("jump_url")
      expect(json.fetch("meta")).to include("count" => 2)
    end

    it "requires authentication" do
      get "/api/v1/games/#{game.game_id}/threads"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/threads/:id" do
    it "returns the thread with its full game-link list" do
      thread = create(:discord_thread)
      create(:thread_game_link, thread: thread, game: game)

      get "/api/v1/threads/#{thread.thread_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "thread_id" => thread.thread_id,
        "thread_name" => thread.thread_name
      )
      links = json.dig("data", "links")
      expect(links.length).to eq(1)
      expect(links.first).to include("thread_id" => thread.thread_id, "gamedb_game_id" => game.game_id)
    end

    it "404s for an unknown thread" do
      get "/api/v1/threads/999999999999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      thread = create(:discord_thread)

      get "/api/v1/threads/#{thread.thread_id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/threads" do
    let(:snowflake) { SecureRandom.random_number(10**18).to_s }
    let(:payload) do
      { data: { thread_id: snowflake, forum_channel_id: "123456", thread_name: "ff7 replay club" } }
    end

    it "creates a new thread as the service and returns 201" do
      expect {
        post "/api/v1/threads", params: payload, headers: service_headers, as: :json
      }.to change(DiscordThread, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "thread_id" => snowflake,
        "forum_channel_id" => "123456",
        "thread_name" => "ff7 replay club",
        "is_archived" => "N",
        "skip_linking" => "N"
      )
    end

    it "allows an admin" do
      post "/api/v1/threads", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "refreshes only the sync columns on an existing thread (200)" do
      thread = create(:discord_thread, skip_linking: "Y")
      original_created_at = thread.created_at

      expect {
        post "/api/v1/threads",
          params: { data: { thread_id: thread.thread_id, forum_channel_id: "999", thread_name: "renamed",
            is_archived: "Y", last_seen_at: "2026-07-01T00:00:00Z", skip_linking: "N",
            created_at: "2000-01-01T00:00:00Z" } },
          headers: service_headers, as: :json
      }.not_to change(DiscordThread, :count)

      expect(response).to have_http_status(:ok)
      thread.reload
      expect(thread.thread_name).to eq("renamed")
      expect(thread.forum_channel_id).to eq("999")
      expect(thread.is_archived).to eq("Y")
      expect(thread.last_seen_at).to eq(Time.zone.parse("2026-07-01T00:00:00Z"))
      expect(thread.skip_linking).to eq("Y")
      expect(thread.created_at).to be_within(1.second).of(original_created_at)
    end

    it "never writes the derived gamedb_game_id" do
      post "/api/v1/threads",
        params: { data: payload[:data].merge(gamedb_game_id: game.game_id) },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "gamedb_game_id")).to be_nil
      expect(DiscordThread.find(snowflake).gamedb_game_id).to be_nil
    end

    it "400s when thread_id is missing" do
      post "/api/v1/threads",
        params: { data: { forum_channel_id: "1", thread_name: "no id" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/threads", params: { thread_id: snowflake }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "422s when thread_name is missing" do
      post "/api/v1/threads",
        params: { data: { thread_id: snowflake, forum_channel_id: "1" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/threads", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(DiscordThread, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post "/api/v1/threads", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/threads/:id" do
    it "updates mutable columns as the service" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { skip_linking: "Y", is_archived: "Y", thread_name: "archived thread" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "skip_linking" => "Y",
        "is_archived" => "Y",
        "thread_name" => "archived thread"
      )
      thread.reload
      expect(thread.skip_linking).to eq("Y")
      expect(thread.is_archived).to eq("Y")
    end

    it "allows an admin" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { thread_name: "admin renamed" } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(thread.reload.thread_name).to eq("admin renamed")
    end

    it "ignores the PK and the derived gamedb_game_id" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { thread_id: "43", gamedb_game_id: game.game_id, thread_name: "kept" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(DiscordThread.exists?(thread.thread_id)).to be(true)
      reloaded = DiscordThread.find(thread.thread_id)
      expect(reloaded.thread_name).to eq("kept")
      expect(reloaded.gamedb_game_id).to be_nil
    end

    it "422s for an invalid is_archived flag" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { is_archived: "X" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(thread.reload.is_archived).to eq("N")
    end

    it "404s for an unknown thread" do
      patch "/api/v1/threads/999999999999999999",
        params: { data: { thread_name: "nope" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "forbids a regular user" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { thread_name: "hijacked" } }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(thread.reload.thread_name).not_to eq("hijacked")
    end

    it "requires authentication" do
      thread = create(:discord_thread)

      patch "/api/v1/threads/#{thread.thread_id}",
        params: { data: { thread_name: "nope" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
