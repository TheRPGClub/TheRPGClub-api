# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the scheduled release announcements (bot parity #43/#109):
# the game-scoped list, the service-only due feed (with its missed-window
# sweep), CRUD + skip on the release_id-keyed rows, and the bulk sync that
# rebuilds a game's schedule and applies canonicality.
RSpec.describe "api/v1/release_announcements behavior", type: :request do
  describe "GET /api/v1/games/:id/release_announcements" do
    it "lists only the game's announcements ordered by announce_at with pagination meta" do
      game = create(:game)
      release_late = create(:release, game: game)
      release_early = create(:release, game: game)
      late = create(:release_announcement, release: release_late, announce_at: Time.utc(2031, 1, 8))
      early = create(:release_announcement, release: release_early, announce_at: Time.utc(2031, 1, 1))
      create(:release_announcement) # other game

      get "/api/v1/games/#{game.game_id}/release_announcements", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |a| a.fetch("release_id") })
        .to eq([ early.release_id, late.release_id ])
      expect(json.fetch("data").first).to include(
        "release_id" => release_early.release_id,
        "sent_at" => nil,
        "skipped_at" => nil,
        "skip_reason" => nil
      )
      expect(json.fetch("meta")).to include("page" => 1, "count" => 2)
    end

    it "requires authentication" do
      get "/api/v1/games/1/release_announcements"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/release_announcements/due" do
    it "returns pending, due, still-upcoming canonical announcements with the joined shape" do
      game = create(:game, igdb_url: "https://www.igdb.com/games/due-spec")
      platform = create(:platform, platform_abbreviation: "DUE")
      due_release = create(:release, game: game, platform: platform, release_date: 5.days.from_now)
      create(:release_announcement, release: due_release, announce_at: 1.hour.ago)

      # Not yet due.
      create(:release_announcement, release: create(:release, release_date: 20.days.from_now), announce_at: 1.hour.from_now)
      # Already sent.
      create(:release_announcement,
        release: create(:release, release_date: 5.days.from_now), announce_at: 1.hour.ago, sent_at: Time.current)
      # Non-canonical: its game has an earlier release, so the later one is excluded.
      other_game = create(:game)
      create(:release, game: other_game, release_date: 5.days.from_now)
      non_canonical = create(:release, game: other_game, release_date: 10.days.from_now)
      create(:release_announcement, release: non_canonical, announce_at: 1.hour.ago)

      get "/api/v1/release_announcements/due", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |row| row.fetch("release_id") }).to eq([ due_release.release_id ])
      row = json.fetch("data").first
      expect(row).to include(
        "id" => due_release.release_id,
        "game_id" => game.game_id,
        "title" => game.title,
        "platform_name" => platform.platform_name,
        "platform_abbreviation" => "DUE",
        "igdb_url" => "https://www.igdb.com/games/due-spec"
      )
      expect(row.fetch("announce_at")).to be_present
      expect(row.fetch("release_date")).to be_present
    end

    it "stamps pending announcements whose release already shipped as release-window-missed" do
      shipped = create(:release, release_date: 1.day.ago)
      missed = create(:release_announcement, release: shipped, announce_at: 2.days.ago)

      get "/api/v1/release_announcements/due", headers: service_headers

      expect(json.fetch("data")).to eq([])
      missed.reload
      expect(missed.skipped_at).to be_present
      expect(missed.skip_reason).to eq("release-window-missed")
    end

    it "bounds the feed with limit, keeping the earliest announce_at first" do
      first = create(:release_announcement, release: create(:release, release_date: 5.days.from_now), announce_at: 2.hours.ago)
      create(:release_announcement, release: create(:release, release_date: 5.days.from_now), announce_at: 1.hour.ago)

      get "/api/v1/release_announcements/due", params: { limit: 1 }, headers: service_headers

      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first.fetch("release_id")).to eq(first.release_id)
    end

    it "is service-only: even an admin is forbidden" do
      get "/api/v1/release_announcements/due", headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      get "/api/v1/release_announcements/due"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/release_announcements/:id" do
    it "shows the announcement to any authenticated user" do
      announcement = create(:release_announcement, announce_at: Time.utc(2031, 3, 1, 12))

      get "/api/v1/release_announcements/#{announcement.release_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_id" => announcement.release_id, "sent_at" => nil)
      expect(json.dig("data", "announce_at")).to be_present
    end

    it "404s for an unknown id" do
      get "/api/v1/release_announcements/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/release_announcements/1"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/release_announcements" do
    let(:release) { create(:release, release_date: Time.utc(2031, 6, 1)) }
    let(:payload) { { data: { release_id: release.release_id, announce_at: "2031-05-25T00:00:00Z" } } }

    it "schedules an announcement as the service" do
      expect {
        post "/api/v1/release_announcements", params: payload, headers: service_headers, as: :json
      }.to change(GamedbReleaseAnnouncement, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("release_id" => release.release_id, "sent_at" => nil, "skipped_at" => nil)
      expect(GamedbReleaseAnnouncement.find(release.release_id).announce_at).to eq(Time.utc(2031, 5, 25))
    end

    it "allows an admin user" do
      post "/api/v1/release_announcements", params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/release_announcements", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbReleaseAnnouncement, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s when announce_at is missing" do
      post "/api/v1/release_announcements",
        params: { data: { release_id: release.release_id } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Announce at")
    end

    it "422s for an unknown release_id" do
      post "/api/v1/release_announcements",
        params: { data: { release_id: 999_999_999, announce_at: "2031-05-25T00:00:00Z" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when the release is already scheduled" do
      create(:release_announcement, release: release)

      post "/api/v1/release_announcements", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("duplicate value violates a unique constraint")
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/release_announcements",
        params: { release_id: release.release_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/release_announcements", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/release_announcements/:id" do
    it "reschedules a pending announcement" do
      announcement = create(:release_announcement, announce_at: Time.utc(2031, 5, 25))

      patch "/api/v1/release_announcements/#{announcement.release_id}",
        params: { data: { announce_at: "2031-05-20T08:00:00Z" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(announcement.reload.announce_at).to eq(Time.utc(2031, 5, 20, 8))
    end

    it "marks delivery state (the bot's sent_at PATCH)" do
      announcement = create(:release_announcement)

      patch "/api/v1/release_announcements/#{announcement.release_id}",
        params: { data: { sent_at: "2031-05-25T09:30:00Z" } },
        headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "sent_at")).to be_present
      expect(announcement.reload.sent_at).to eq(Time.utc(2031, 5, 25, 9, 30))
    end

    it "accepts PUT as an alias" do
      announcement = create(:release_announcement, announce_at: Time.utc(2031, 5, 25))

      put "/api/v1/release_announcements/#{announcement.release_id}",
        params: { data: { announce_at: "2031-05-21T00:00:00Z" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(announcement.reload.announce_at).to eq(Time.utc(2031, 5, 21))
    end

    it "forbids a regular user" do
      announcement = create(:release_announcement, announce_at: Time.utc(2031, 5, 25))

      patch "/api/v1/release_announcements/#{announcement.release_id}",
        params: { data: { announce_at: "2031-01-01T00:00:00Z" } },
        headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(announcement.reload.announce_at).to eq(Time.utc(2031, 5, 25))
    end

    it "404s for an unknown id" do
      patch "/api/v1/release_announcements/999999999",
        params: { data: { announce_at: "2031-01-01T00:00:00Z" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      patch "/api/v1/release_announcements/1", params: { data: { announce_at: "2031-01-01T00:00:00Z" } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/release_announcements/:id" do
    it "deletes the announcement" do
      announcement = create(:release_announcement)

      delete "/api/v1/release_announcements/#{announcement.release_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(GamedbReleaseAnnouncement.exists?(announcement.release_id)).to be(false)
    end

    it "forbids a regular user" do
      announcement = create(:release_announcement)

      delete "/api/v1/release_announcements/#{announcement.release_id}", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(GamedbReleaseAnnouncement.exists?(announcement.release_id)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/release_announcements/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      delete "/api/v1/release_announcements/1"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/release_announcements/:id/skip" do
    it "stamps skipped_at with the supplied reason" do
      announcement = create(:release_announcement)

      post "/api/v1/release_announcements/#{announcement.release_id}/skip",
        params: { data: { skip_reason: "manual-skip" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "skipped_at")).to be_present
      expect(json.dig("data", "skip_reason")).to eq("manual-skip")
      expect(announcement.reload.skipped_at).to be_present
    end

    it "works without a body, leaving skip_reason null" do
      announcement = create(:release_announcement)

      post "/api/v1/release_announcements/#{announcement.release_id}/skip", headers: service_headers

      expect(response).to have_http_status(:ok)
      announcement.reload
      expect(announcement.skipped_at).to be_present
      expect(announcement.skip_reason).to be_nil
    end

    it "forbids a regular user" do
      announcement = create(:release_announcement)

      post "/api/v1/release_announcements/#{announcement.release_id}/skip", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
      expect(announcement.reload.skipped_at).to be_nil
    end

    it "404s for an unknown id" do
      post "/api/v1/release_announcements/999999999/skip", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/release_announcements/1/skip"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/games/:id/release_announcements (bulk sync)" do
    let(:game) { create(:game) }

    it "builds the schedule from the releases and applies canonicality" do
      canonical = create(:release, game: game, release_date: Time.utc(2031, 6, 1))
      same_day = create(:release, game: game, release_date: Time.utc(2031, 6, 1))
      port = create(:release, game: game, release_date: Time.utc(2031, 7, 1))
      undated = create(:release, game: game, release_date: nil)

      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("upserted" => 3, "restored" => 0, "skipped" => 2)

      canonical_row = GamedbReleaseAnnouncement.find(canonical.release_id)
      expect(canonical_row.announce_at).to eq(Time.utc(2031, 5, 25))
      expect(canonical_row.skipped_at).to be_nil

      expect(GamedbReleaseAnnouncement.find(same_day.release_id).skip_reason).to eq("same-day-platform-duplicate")
      expect(GamedbReleaseAnnouncement.find(port.release_id).skip_reason).to eq("port-only-release")
      expect(GamedbReleaseAnnouncement.exists?(undated.release_id)).to be(false)

      # Re-running is a no-op once the schedule is settled.
      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers
      expect(json.fetch("data")).to eq("upserted" => 0, "restored" => 0, "skipped" => 0)
    end

    it "restores a canonicality skip that no longer qualifies" do
      release = create(:release, game: game, release_date: Time.utc(2031, 6, 1))
      stale = create(:release_announcement,
        release: release, announce_at: Time.utc(2031, 5, 25),
        skipped_at: Time.current, skip_reason: "port-only-release")

      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq("upserted" => 0, "restored" => 1, "skipped" => 0)
      stale.reload
      expect(stale.skipped_at).to be_nil
      expect(stale.skip_reason).to be_nil
    end

    it "never touches rows the send loop already owns" do
      create(:release, game: game, release_date: Time.utc(2031, 6, 1))
      port = create(:release, game: game, release_date: Time.utc(2031, 7, 1))
      sent = create(:release_announcement,
        release: port, announce_at: Time.utc(2031, 6, 28), sent_at: Time.utc(2031, 6, 28, 12))

      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers

      expect(json.fetch("data")).to eq("upserted" => 1, "restored" => 0, "skipped" => 0)
      sent.reload
      expect(sent.announce_at).to eq(Time.utc(2031, 6, 28))
      expect(sent.sent_at).to be_present
      expect(sent.skip_reason).to be_nil
    end

    it "accepts PUT as an alias" do
      create(:release, game: game, release_date: Time.utc(2031, 6, 1))

      put "/api/v1/games/#{game.game_id}/release_announcements", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("upserted" => 1)
    end

    it "forbids a regular user" do
      patch "/api/v1/games/#{game.game_id}/release_announcements", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      patch "/api/v1/games/#{game.game_id}/release_announcements"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
