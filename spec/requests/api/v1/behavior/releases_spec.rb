# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the admin/service-only Manual Release writes: create
# (POST /api/v1/games/:id/releases, the bot's addReleaseInfo), edit and delete
# (PATCH/DELETE /api/v1/releases/:id, the Game Edit page). Reads live on
# GET /api/v1/games/:id/releases, covered in the games behavior spec.
RSpec.describe "api/v1/releases behavior", type: :request do
  let(:game) { create(:game) }
  let(:platform) { create(:platform) }
  let(:region) { create(:region) }
  let(:payload) do
    {
      data: {
        platform_id: platform.platform_id,
        region_id: region.region_id,
        format: "Physical",
        release_date: "2024-05-10",
        notes: "collector edition"
      }
    }
  end

  # Simulates Gamedb::ReleaseSync adopting `release` (Manual -> IGDB) after
  # the request loaded it but before it got the game's row lock.
  def adopt_while_waiting_for_the_game_lock(release)
    allow_any_instance_of(GamedbGame).to receive(:lock!).and_wrap_original do |original, *args|
      GamedbRelease.where(release_id: release.release_id).update_all(source: "igdb")
      original.call(*args)
    end
  end

  describe "POST /api/v1/games/:id/releases" do
    it "creates the release with platform/region labels flattened in" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
      }.to change(GamedbRelease.where(game_id: game.game_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "game_id" => game.game_id,
        "platform_id" => platform.platform_id,
        "region_id" => region.region_id,
        "format" => "Physical",
        "notes" => "collector edition",
        "platform_code" => platform.platform_code,
        "platform_name" => platform.platform_name,
        "region_code" => region.region_code,
        "region_name" => region.region_name
      )

      expect(json.dig("data", "release_date")).to eq("2024-05-10")
    end

    it "creates an exact-day Release, or a TBA Release when no date is given" do
      post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
      expect(json.dig("data", "date_precision")).to eq("day")

      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: payload[:data].merge(release_date: nil) }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("release_date" => nil, "date_precision" => "tba")
    end

    it "creates a Release at each Date Precision, a vague date on the first day of its period" do
      {
        "day" => "2027-08-14",
        "month" => "2027-08-01",
        "quarter" => "2027-07-01",
        "year" => "2027-01-01",
        "tba" => nil
      }.each do |precision, date|
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: payload[:data].merge(release_date: date, date_precision: precision) },
          headers: service_headers, as: :json

        expect(response).to have_http_status(:created)
        expect(json.fetch("data")).to include("release_date" => date, "date_precision" => precision)
      end
    end

    it "422s for an unparseable date instead of making the Release TBA" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: payload[:data].merge(release_date: "next spring") }, headers: service_headers, as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Release date is not a valid date")
    end

    it "creates a TBA Release when the date is omitted entirely" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: region.region_id, date_precision: "tba" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("release_date" => nil, "date_precision" => "tba")
    end

    it "treats a null Date Precision as omitted (day)" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: payload[:data].merge(date_precision: nil) }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "date_precision")).to eq("day")
    end

    it "422s for a TBA Release with a date" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: payload[:data].merge(date_precision: "tba") }, headers: service_headers, as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("must be empty for a TBA Release")
    end

    %w[day month quarter year].each do |precision|
      it "422s for a #{precision} Release without a date" do
        expect {
          post "/api/v1/games/#{game.game_id}/releases",
            params: { data: payload[:data].merge(release_date: nil, date_precision: precision) },
            headers: service_headers, as: :json
        }.not_to change(GamedbRelease, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to include("Release date is required unless the Release is TBA")
      end
    end

    it "422s for a vague date that is not the first day of its period" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: payload[:data].merge(release_date: "2027-08-14", date_precision: "quarter") },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("must be the first day of its quarter")
    end

    it "422s for an unknown Date Precision" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: payload[:data].merge(date_precision: "fortnight") }, headers: service_headers, as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Date precision")
    end

    it "keeps the calendar day of a timestamp sent as the release date" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: payload[:data].merge(release_date: "2024-05-10T00:00:00.000Z") }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "release_date")).to eq("2024-05-10")
    end

    it "creates a Manual Release" do
      post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "source")).to eq("manual")
    end

    it "ignores a source sent in the body, so the write is always a Manual Release" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: payload[:data].merge(source: "igdb") }, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "source")).to eq("manual")
    end

    it "bumps the game's updated_at so the cached relations invalidate" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
      }.to change { game.reload.updated_at }
    end

    it "allows duplicates (plain insert, matching the bot)" do
      2.times do
        post "/api/v1/games/#{game.game_id}/releases", params: payload, headers: service_headers, as: :json
        expect(response).to have_http_status(:created)
      end

      expect(GamedbRelease.where(game_id: game.game_id).count).to eq(2)
    end

    it "allows an admin user" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: payload, headers: auth_headers_for(create(:user, :admin)), as: :json

      expect(response).to have_http_status(:created)
    end

    it "accepts a null format" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: region.region_id } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "format")).to be_nil
      expect(json.dig("data", "release_date")).to be_nil
    end

    it "422s for a format outside Physical/Digital" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: region.region_id, format: "Streaming" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Format")
    end

    it "422s when platform_id is missing" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: { data: { region_id: region.region_id } }, headers: service_headers, as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown region_id" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { data: { platform_id: platform.platform_id, region_id: 999_999_999 } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Region")
    end

    it "404s for an unknown game" do
      post "/api/v1/games/999999999/releases", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/games/#{game.game_id}/releases",
        params: { platform_id: platform.platform_id }, headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "forbids a regular user" do
      expect {
        post "/api/v1/games/#{game.game_id}/releases",
          params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq("error" => "forbidden")
    end

    it "requires authentication" do
      post "/api/v1/games/#{game.game_id}/releases", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/releases/:id" do
    let(:release) do
      create(:release, game:, platform:, region:, source: "manual", format: "Physical",
        release_date: Date.new(2027, 8, 14), date_precision: "day", notes: "launch")
    end
    let(:admin) { create(:user, :admin) }

    def patch_release(data = nil, headers: auth_headers_for(admin), id: release.release_id, **fields)
      patch "/api/v1/releases/#{id}", params: { data: data || fields }, headers:, as: :json
    end

    it "edits every field of a Manual Release and returns it with labels flattened in" do
      other_platform = create(:platform)
      other_region = create(:region)

      patch_release(platform_id: other_platform.platform_id, region_id: other_region.region_id, format: "Digital",
        release_date: "2027-07-01", date_precision: "quarter", notes: "delayed")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include(
        "release_id" => release.release_id,
        "game_id" => game.game_id,
        "platform_id" => other_platform.platform_id,
        "platform_code" => other_platform.platform_code,
        "region_id" => other_region.region_id,
        "region_code" => other_region.region_code,
        "format" => "Digital",
        "release_date" => "2027-07-01",
        "date_precision" => "quarter",
        "notes" => "delayed",
        "source" => "manual"
      )
      expect(release.reload).to have_attributes(date_precision: "quarter", notes: "delayed")
    end

    it "changes only the fields sent" do
      patch_release(notes: "corrected")

      expect(response).to have_http_status(:ok)
      expect(release.reload).to have_attributes(notes: "corrected", format: "Physical",
        release_date: Date.new(2027, 8, 14), date_precision: "day", platform_id: platform.platform_id)
    end

    it "makes the Release TBA when its date is cleared without a Date Precision" do
      patch_release(release_date: nil)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_date" => nil, "date_precision" => "tba")
    end

    it "makes a TBA Release an exact day when it is given a date without a Date Precision" do
      tba = create(:release, game:, platform:, region:, source: "manual")

      patch_release({ release_date: "2027-09-02" }, id: tba.release_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_date" => "2027-09-02", "date_precision" => "day")
    end

    it "422s for an unparseable date and keeps the Release's date" do
      patch_release(release_date: "2027-13-45")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Release date is not a valid date")
      expect(release.reload).to have_attributes(release_date: Date.new(2027, 8, 14), date_precision: "day")
    end

    it "makes a vague Release an exact day when given a date inside its period without a Date Precision" do
      month = create(:release, game:, platform:, region:, source: "manual",
        release_date: Date.new(2027, 8, 1), date_precision: "month")

      patch_release({ release_date: "2027-08-20" }, id: month.release_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_date" => "2027-08-20", "date_precision" => "day")
    end

    it "keeps a vague Release vague when given the start of another period without a Date Precision" do
      quarter = create(:release, game:, platform:, region:, source: "manual",
        release_date: Date.new(2027, 7, 1), date_precision: "quarter")

      patch_release({ release_date: "2027-10-01" }, id: quarter.release_id)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_date" => "2027-10-01", "date_precision" => "quarter")
    end

    it "still 422s a vague Date Precision sent with a date that isn't its period start" do
      patch_release(release_date: "2027-08-20", date_precision: "month")

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses with a 422 when an IGDB refresh adopted the Release while the edit waited" do
      adopt_while_waiting_for_the_game_lock(release)

      patch_release(notes: "x")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_release")
      expect(release.reload).to have_attributes(source: "igdb", notes: "launch")
    end

    it "makes a Release TBA when sent TBA with a null date" do
      patch_release(release_date: nil, date_precision: "tba")

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("release_date" => nil, "date_precision" => "tba")
    end

    it "422s for TBA while the Release keeps its date" do
      patch_release(date_precision: "tba")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("must be empty for a TBA Release")
      expect(release.reload.date_precision).to eq("day")
    end

    it "422s for a non-TBA precision without a date" do
      patch_release(release_date: nil, date_precision: "year")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Release date is required unless the Release is TBA")
    end

    it "422s for an unknown Date Precision or format" do
      patch_release(date_precision: "fortnight")
      expect(response).to have_http_status(:unprocessable_content)

      patch_release(format: "Streaming")
      expect(response).to have_http_status(:unprocessable_content)
      expect(release.reload).to have_attributes(date_precision: "day", format: "Physical")
    end

    it "ignores source and game_id sent in the body" do
      other_game = create(:game)

      patch_release(source: "igdb", game_id: other_game.game_id, notes: "x")

      expect(response).to have_http_status(:ok)
      expect(release.reload).to have_attributes(source: "manual", game_id: game.game_id)
    end

    it "refuses an IGDB Release with a 422" do
      igdb = create(:release, game:, platform:, region:, source: "igdb", release_date: Date.new(2027, 8, 14))

      patch_release({ notes: "x" }, id: igdb.release_id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_release")
      expect(igdb.reload.notes).to be_nil
    end

    it "bumps the game's updated_at so the cached relations invalidate" do
      release

      expect { patch_release(notes: "x") }.to change { game.reload.updated_at }
    end

    it "reschedules the game's release announcement from the new date" do
      announcement = create(:release_announcement, release:, announce_at: Time.utc(2027, 8, 7))

      patch_release(release_date: "2027-09-14")

      expect(response).to have_http_status(:ok)
      expect(announcement.reload.announce_at).to eq(Time.utc(2027, 9, 7))
    end

    it "drops an unsent announcement when the Release is no longer an exact day" do
      create(:release_announcement, release:)

      patch_release(release_date: "2027-08-01", date_precision: "month")

      expect(response).to have_http_status(:ok)
      expect(GamedbReleaseAnnouncement.where(release_id: release.release_id)).not_to exist
    end

    it "marks the game announced when going vague drops a due announcement the bot may be sending" do
      create(:release_announcement, release:, announce_at: 1.hour.ago)

      patch_release(release_date: "2027-08-01", date_precision: "month")

      expect(response).to have_http_status(:ok)
      expect(game.reload.release_announced_at).to be_present
    end

    it "allows the service token" do
      patch_release({ notes: "x" }, headers: service_headers)

      expect(response).to have_http_status(:ok)
    end

    it "forbids a regular user" do
      patch_release({ notes: "x" }, headers: auth_headers_for(create(:user)))

      expect(response).to have_http_status(:forbidden)
      expect(release.reload.notes).to eq("launch")
    end

    it "requires authentication" do
      patch_release({ notes: "x" }, headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unknown Release" do
      patch_release({ notes: "x" }, id: 999_999_999)

      expect(response).to have_http_status(:not_found)
    end

    it "400s when the data envelope is missing" do
      patch "/api/v1/releases/#{release.release_id}", params: { notes: "x" }, headers: auth_headers_for(admin), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE /api/v1/releases/:id" do
    let!(:release) do
      create(:release, game:, platform:, region:, source: "manual", release_date: Date.new(2027, 8, 14))
    end
    let(:admin) { create(:user, :admin) }

    def delete_release(headers: auth_headers_for(admin), id: release.release_id)
      delete "/api/v1/releases/#{id}", headers:, as: :json
    end

    it "deletes a Manual Release" do
      expect { delete_release }.to change(GamedbRelease, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "deletes the Release's announcement with it" do
      create(:release_announcement, release:)

      delete_release

      expect(response).to have_http_status(:no_content)
      expect(GamedbReleaseAnnouncement.where(release_id: release.release_id)).not_to exist
    end

    it "keeps when a sent announcement went out on the game" do
      sent_at = Time.utc(2027, 8, 7, 12)
      create(:release_announcement, release:, sent_at:)

      delete_release

      expect(response).to have_http_status(:no_content)
      expect(game.reload.release_announced_at).to eq(sent_at)
    end

    it "bumps the game's updated_at so the cached relations invalidate" do
      expect { delete_release }.to change { game.reload.updated_at }
    end

    it "refuses with a 422 when an IGDB refresh adopted the Release while the delete waited" do
      adopt_while_waiting_for_the_game_lock(release)

      expect { delete_release }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_release")
    end

    it "marks the game announced when it deletes a due announcement the bot may be sending" do
      create(:release_announcement, release:, announce_at: 1.hour.ago)

      delete_release

      expect(response).to have_http_status(:no_content)
      expect(game.reload.release_announced_at).to be_within(1.minute).of(Time.current)
    end

    it "leaves the game unannounced when the deleted announcement wasn't due yet" do
      create(:release_announcement, release:, announce_at: 1.week.from_now)

      delete_release

      expect(response).to have_http_status(:no_content)
      expect(game.reload.release_announced_at).to be_nil
    end

    it "leaves the game unannounced when the deleted announcement was skipped" do
      create(:release_announcement, release:, announce_at: 1.hour.ago, skipped_at: 1.hour.ago,
        skip_reason: "port-only-release")

      delete_release

      expect(game.reload.release_announced_at).to be_nil
    end

    it "refuses an IGDB Release with a 422" do
      igdb = create(:release, game:, platform:, region:, source: "igdb", release_date: Date.new(2027, 8, 14))

      expect { delete_release(id: igdb.release_id) }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("igdb_release")
    end

    it "allows the service token" do
      delete_release(headers: service_headers)

      expect(response).to have_http_status(:no_content)
    end

    it "forbids a regular user" do
      expect { delete_release(headers: auth_headers_for(create(:user))) }.not_to change(GamedbRelease, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      delete_release(headers: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "404s for an unknown Release" do
      delete_release(id: 999_999_999)

      expect(response).to have_http_status(:not_found)
    end
  end
end
