# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the per-user avatar-change log (#105) and the aggregate
# leaderboard counts (#145): reads are open to any authenticated principal,
# the write is service-only. The binary avatar_blob column must never leak
# into a response.
RSpec.describe "api/v1/user_avatar_history behavior", type: :request do
  let(:owner) { create(:user) }

  describe "GET /api/v1/users/:user_id/avatar_history" do
    it "lists only that user's events newest first, without avatar_blob" do
      older = create(:avatar_history_event, user: owner, changed_at: 2.days.ago)
      newer = create(:avatar_history_event, user: owner, changed_at: 1.day.ago)
      create(:avatar_history_event) # another user's event

      get "/api/v1/users/#{owner.user_id}/avatar_history", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |e| e.fetch("event_id") }).to eq([ newer.event_id, older.event_id ])
      expect(json.fetch("data").first).to include(
        "event_id" => newer.event_id,
        "user_id" => owner.user_id,
        "avatar_hash" => newer.avatar_hash,
        "avatar_url" => newer.avatar_url
      )
      expect(json.fetch("data").first).to have_key("changed_at")
      expect(json.fetch("data")).to all(satisfy { |e| !e.key?("avatar_blob") })
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "paginates with page/per" do
      create_list(:avatar_history_event, 3, user: owner)

      get "/api/v1/users/#{owner.user_id}/avatar_history",
        params: { per: 2, page: 2 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 2, "page" => 2, "count" => 3, "pages" => 2)
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/avatar_history"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/users/:user_id/avatar_history" do
    let(:payload) { { data: { avatar_hash: "abc123", avatar_url: "https://cdn.example.test/a.png" } } }

    it "records an event as the service, DB-stamping changed_at" do
      expect {
        post "/api/v1/users/#{owner.user_id}/avatar_history",
          params: payload, headers: service_headers, as: :json
      }.to change(RpgClubUserAvatarHistory.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "avatar_hash" => "abc123",
        "avatar_url" => "https://cdn.example.test/a.png"
      )
      expect(json.dig("data", "event_id")).to be_present
      expect(json.dig("data", "changed_at")).to be_present
      expect(json.fetch("data")).not_to have_key("avatar_blob")
    end

    it "ignores server-managed fields in the body" do
      post "/api/v1/users/#{owner.user_id}/avatar_history",
        params: { data: { avatar_hash: "abc", changed_at: "2000-01-01T00:00:00Z",
                          event_id: 999_999_999, avatar_blob: "raw-bytes" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      record = RpgClubUserAvatarHistory.find(json.dig("data", "event_id"))
      expect(record.event_id).not_to eq(999_999_999)
      expect(record.changed_at).to be > Time.utc(2020, 1, 1)
      expect(record.avatar_blob).to be_nil
    end

    it "forbids a user token, even the owner's" do
      expect {
        post "/api/v1/users/#{owner.user_id}/avatar_history",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(RpgClubUserAvatarHistory, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/avatar_history",
        params: { avatar_hash: "bare" }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/avatar_history", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/users/avatar_history_counts" do
    it "aggregates change counts for active non-bot members, ordered by display name" do
      prefix = "zzcount#{SecureRandom.hex(4)}"
      member_a = create(:user, global_name: "#{prefix} aa")
      member_b = create(:user, global_name: "#{prefix} bb")
      create_list(:avatar_history_event, 2, user: member_a)
      create(:avatar_history_event, user: member_b)

      bot = create(:user, is_bot: true)
      departed = create(:user, server_left_at: 1.day.ago)
      no_events = create(:user)
      create(:avatar_history_event, user: bot)
      create(:avatar_history_event, user: departed)

      get "/api/v1/users/avatar_history_counts", params: { per: 500 }, headers: auth_headers_for(no_events)

      expect(response).to have_http_status(:ok)
      rows = json.fetch("data")
      row_a = rows.find { |r| r.fetch("user_id") == member_a.user_id }
      row_b = rows.find { |r| r.fetch("user_id") == member_b.user_id }
      expect(row_a).to include("global_name" => member_a.global_name, "avatar_change_count" => 2)
      expect(row_b).to include("global_name" => member_b.global_name, "avatar_change_count" => 1)
      expect(rows.index(row_a)).to be < rows.index(row_b)

      listed_ids = rows.map { |r| r.fetch("user_id") }
      expect(listed_ids).not_to include(bot.user_id, departed.user_id, no_events.user_id)
      expect(json.fetch("meta")).to include("page" => 1)
      expect(json.dig("meta", "count")).to be >= 2
    end

    it "paginates the grouped rows with an explicit total count" do
      create_list(:avatar_history_event, 1, user: create(:user))
      create_list(:avatar_history_event, 1, user: create(:user))

      get "/api/v1/users/avatar_history_counts", params: { per: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("meta")).to include("per" => 1)
      expect(json.dig("meta", "pages")).to be >= 2
    end

    it "requires authentication" do
      get "/api/v1/users/avatar_history_counts"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
