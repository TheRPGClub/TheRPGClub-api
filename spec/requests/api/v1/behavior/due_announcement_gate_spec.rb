# frozen_string_literal: true

require "rails_helper"

# The bot polls GET /release_announcements/due every hour. Until the next
# announcement comes due, the API answers from a gate on the machine's disk
# (Gamedb::DueAnnouncementGate) without touching Neon, so the hourly poll
# doesn't wake the database.
RSpec.describe "release announcements due gate", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.utc(2027, 3, 1, 12) }

  def due_queries
    count = 0
    callback = lambda do |*, payload|
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(BEGIN|COMMIT|SAVEPOINT|RELEASE|ROLLBACK)/)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get "/api/v1/release_announcements/due", headers: service_headers
    end
    expect(response).to have_http_status(:ok)
    count
  end

  def ids = json.fetch("data").map { |row| row.fetch("release_id") }

  def upcoming(announce_at)
    release = create(:release, release_date: (announce_at + 7.days).to_date)
    create(:release_announcement, release: release, announce_at: announce_at)
    release
  end

  it "answers without the database until the next announcement comes due, then offers it" do
    release = upcoming(now + 2.days)

    travel_to(now) do
      expect(due_queries).to be > 0
      expect(ids).to be_empty

      expect(due_queries).to eq(0)
      expect(ids).to be_empty
    end

    travel_to(now + 2.days + 1.minute) do
      expect(due_queries).to be > 0
      expect(ids).to eq([ release.release_id ])
    end
  end

  it "looks again once an announcement changes" do
    travel_to(now) do
      due_queries
      expect(due_queries).to eq(0)

      release = upcoming(now - 1.minute)

      expect(due_queries).to be > 0
      expect(ids).to eq([ release.release_id ])
    end
  end

  it "looks again once a Release write rebuilds a game's schedule" do
    game = create(:game)

    travel_to(now) do
      due_queries
      expect(due_queries).to eq(0)

      post "/api/v1/games/#{game.game_id}/releases", headers: service_headers, as: :json,
        params: { data: { platform_id: create(:platform).platform_id, region_id: create(:region).region_id,
                          release_date: (now + 3.days).to_date.iso8601 } }
      expect(response).to have_http_status(:created)

      expect(due_queries).to be > 0
      expect(ids).to eq([ GamedbRelease.where(game_id: game.game_id).sole.release_id ])
    end
  end

  it "keeps offering due announcements until they are sent" do
    release = upcoming(now - 1.hour)

    travel_to(now) do
      due_queries
      expect(ids).to eq([ release.release_id ])
      expect(due_queries).to be > 0

      patch "/api/v1/release_announcements/#{release.release_id}", headers: service_headers, as: :json,
        params: { data: { sent_at: now.iso8601 } }
      expect(response).to have_http_status(:ok)

      expect(due_queries).to be > 0
      expect(ids).to be_empty
      expect(due_queries).to eq(0)
    end
  end

  it "looks again after RECHECK even when nothing is scheduled" do
    travel_to(now) do
      due_queries
      expect(due_queries).to eq(0)
    end

    travel_to(now + Gamedb::DueAnnouncementGate::RECHECK + 1.minute) do
      expect(due_queries).to be > 0
    end
  end
end
