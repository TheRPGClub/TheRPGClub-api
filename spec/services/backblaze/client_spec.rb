# frozen_string_literal: true

require "rails_helper"

# Backblaze B2 through Faraday's test adapter: what an upload tells B2.
RSpec.describe Backblaze::Client do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:uploads) { [] }

  around do |example|
    keys = %w[BACKBLAZE_KEY_ID BACKBLAZE_APPLICATION_KEY BACKBLAZE_BUCKET_ID]
    original_env = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV[key] = "test-#{key.downcase}" }
    original_connection = Faraday.default_connection
    Faraday.default_connection = Faraday.new { |builder| builder.adapter(:test, stubs) }
    example.run
  ensure
    Faraday.default_connection = original_connection
    original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    stubs.get(described_class::AUTHORIZE_URL) do
      [ 200, {}, { authorizationToken: "b2-auth", apiInfo: { storageApi: { apiUrl: "https://b2.example.test" } } }.to_json ]
    end
    stubs.get("https://b2.example.test/b2api/v4/b2_get_upload_url") do
      [ 200, {}, { uploadUrl: "https://upload.example.test/up", authorizationToken: "up-auth" }.to_json ]
    end
    stubs.post("https://upload.example.test/up") do |env|
      uploads << env.request_headers
      [ 200, {}, { fileId: "f1" }.to_json ]
    end
  end

  it "uploads with a day's Cache-Control, so browsers keep the image between pages" do
    described_class.new.upload_bytes(object_key: "games/1-x/cover/main.jpg", bytes: "jpeg", content_type: "image/jpeg")

    expect(uploads.size).to eq(1)
    expect(URI.decode_www_form_component(uploads.first.fetch("X-Bz-Info-b2-cache-control")))
      .to eq("public, max-age=86400, stale-while-revalidate=604800")
  end
end
