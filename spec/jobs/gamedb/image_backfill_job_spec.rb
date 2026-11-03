# frozen_string_literal: true

require "rails_helper"

# The image backfill (web parity 2, #338): the bot's
# `/superadmin download-missing-images`, moved into the API. IGDB, the IGDB
# image CDN and Backblaze are stubbed through Faraday's test adapter, so the
# real importer and storage run end to end without touching the network.
RSpec.describe Gamedb::ImageBackfillJob do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:superadmin) { create(:user) }
  let(:run) { ImageBackfillRun.create!(started_by_user_id: superadmin.user_id) }
  let(:uploads) { [] }

  # IGDB `games` answers per IGDB id; an id missing here is "not found".
  let(:igdb_games) do
    {
      101 => [ { id: 101, name: "Chrono Trigger", cover: { image_id: "co101" },
                 artworks: [ { image_id: "ar101", alpha_channel: false, artwork_type: { slug: "artwork" } } ] } ]
    }
  end

  around do |example|
    keys = %w[IGDB_CLIENT_ID IGDB_CLIENT_SECRET BACKBLAZE_KEY_ID BACKBLAZE_APPLICATION_KEY BACKBLAZE_BUCKET_ID]
    original_env = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV[key] = "test-#{key.downcase}" }
    original_connection = Faraday.default_connection
    Faraday.default_connection = Faraday.new { |builder| builder.adapter(:test, stubs) }
    original_pause = described_class.pause_seconds
    described_class.pause_seconds = 0

    example.run
  ensure
    described_class.pause_seconds = original_pause
    Faraday.default_connection = original_connection
    original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    stubs.post(Igdb::Client::TOKEN_URL) { [ 200, {}, { access_token: "token", expires_in: 3600 }.to_json ] }
    stubs.post("#{Igdb::Client::API_BASE_URL}/games") do |env|
      igdb_id = env.request_body[/where id = (\d+)/, 1].to_i
      [ 200, {}, igdb_games.fetch(igdb_id, []).to_json ]
    end
    stubs.get(%r{\A/igdb/image/upload/}) { [ 200, { "Content-Type" => "image/jpeg" }, "jpeg-bytes" ] }
    stubs.get(Backblaze::Client::AUTHORIZE_URL) do
      [ 200, {}, { authorizationToken: "b2-auth", apiInfo: { storageApi: { apiUrl: "https://b2.example.test" } } }.to_json ]
    end
    stubs.get("https://b2.example.test/b2api/v4/b2_get_upload_url") do
      [ 200, {}, { uploadUrl: "https://upload.example.test/up", authorizationToken: "up-auth" }.to_json ]
    end
    stubs.post("https://upload.example.test/up") do |env|
      uploads << env.request_headers["X-Bz-File-Name"]
      [ 200, {}, { fileId: "f#{uploads.size}" }.to_json ]
    end
  end

  it "imports images for each game without any, counting a missing IGDB id as skipped and an import error as failed" do
    downloaded = create(:game, igdb_id: 101)
    create(:game, igdb_id: nil)
    not_on_igdb = create(:game, igdb_id: 103)
    create(:game_image, game: create(:game, igdb_id: 104))

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(
      status: "completed", total: 3, done: 1, skipped: 1, failed: 1,
      started_by_user_id: superadmin.user_id
    )
    expect(run.started_at).to be_present
    expect(run.finished_at).to be >= run.started_at
    expect(run.last_error).to eq("Game #{not_on_igdb.game_id}: IGDB game 103 was not found")
    expect(downloaded.images.pluck(:kind)).to contain_exactly("cover", "artwork")
    expect(uploads.size).to eq(2)
  end

  it "completes an empty run when every game has images" do
    create(:game_image, game: create(:game, igdb_id: 104))

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: "completed", total: 0, done: 0, skipped: 0, failed: 0,
      last_error: nil)
  end

  it "stops the run as failed when IGDB is not configured, instead of failing every game" do
    create(:game, igdb_id: 101)
    create(:game, igdb_id: 102)
    ENV.delete("IGDB_CLIENT_ID")
    ENV.delete("IGDB_CLIENT_SECRET")

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: "failed", total: 2, done: 0, failed: 0,
      last_error: "IGDB_CLIENT_ID must be set")
    expect(run.finished_at).to be_present
  end

  it "does nothing for a run that is no longer queued" do
    create(:game, igdb_id: 101)
    run.update!(status: "completed", finished_at: Time.current)

    described_class.perform_now(run.id)

    expect(run.reload).to have_attributes(status: "completed", total: 0, done: 0)
    expect(uploads).to be_empty
  end
end
