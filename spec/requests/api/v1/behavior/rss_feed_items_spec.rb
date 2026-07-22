# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the RSS seen-item dedup endpoints (#93): the bot checks a
# candidate hash list against what's stored, then bulk-marks new items seen
# with insert-or-ignore semantics on the (feed_id, item_id_hash) PK.
RSpec.describe "api/v1/rss_feed_items behavior", type: :request do
  let(:feed) { create(:rss_feed) }

  describe "GET /api/v1/rss_feeds/:rss_feed_id/items" do
    it "returns only the already-seen subset of the candidate hashes for this feed" do
      seen = create(:rss_feed_item, feed: feed)
      create(:rss_feed_item, feed: feed)
      other_feed_item = create(:rss_feed_item)

      get "/api/v1/rss_feeds/#{feed.feed_id}/items",
        params: { hashes: [ seen.item_id_hash, "never-seen", other_feed_item.item_id_hash ] },
        headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([ seen.item_id_hash ])
    end

    # NOTE: the documented GET-with-JSON-body variant can't be exercised here:
    # ActionDispatch integration rewrites `get ..., as: :json` into a real POST
    # (with an X-HTTP-Method-Override header the app doesn't honor), which
    # routes to #create instead of #index.

    it "returns an empty list when no candidates are supplied" do
      create(:rss_feed_item, feed: feed)

      get "/api/v1/rss_feeds/#{feed.feed_id}/items", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("data" => [])
    end

    it "404s for an unknown feed" do
      get "/api/v1/rss_feeds/999999999/items", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/rss_feeds/#{feed.feed_id}/items"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/rss_feeds/:rss_feed_id/items" do
    it "marks items seen and reports the inserted count" do
      payload = { data: [
        { item_id_hash: "hash-a", title: "New RPG", url: "https://example.com/a",
          published_at: "2026-01-01T00:00:00Z" },
        { item_id_hash: "hash-b" }
      ] }

      expect {
        post "/api/v1/rss_feeds/#{feed.feed_id}/items", params: payload, headers: service_headers, as: :json
      }.to change(feed.items, :count).by(2)

      expect(response).to have_http_status(:created)
      expect(json).to eq("created" => 2)
      row = feed.items.find_by!(item_id_hash: "hash-a")
      expect(row.title).to eq("New RPG")
      expect(row.url).to eq("https://example.com/a")
      expect(row.published_at).to eq(Time.zone.parse("2026-01-01T00:00:00Z"))
    end

    it "skips hashes already recorded (insert-or-ignore)" do
      existing = create(:rss_feed_item, feed: feed)

      expect {
        post "/api/v1/rss_feeds/#{feed.feed_id}/items",
          params: { data: [ { item_id_hash: existing.item_id_hash }, { item_id_hash: "fresh-hash" } ] },
          headers: service_headers, as: :json
      }.to change(feed.items, :count).by(1)

      expect(json).to eq("created" => 1)
    end

    it "dedupes repeated hashes within the batch" do
      expect {
        post "/api/v1/rss_feeds/#{feed.feed_id}/items",
          params: { data: [ { item_id_hash: "twice" }, { item_id_hash: "twice" } ] },
          headers: service_headers, as: :json
      }.to change(feed.items, :count).by(1)

      expect(json).to eq("created" => 1)
    end

    it "skips entries without an item_id_hash" do
      expect {
        post "/api/v1/rss_feeds/#{feed.feed_id}/items",
          params: { data: [ { title: "no hash" }, { item_id_hash: "has-hash" } ] },
          headers: service_headers, as: :json
      }.to change(feed.items, :count).by(1)

      expect(json).to eq("created" => 1)
    end

    it "scopes the rows to the feed in the path" do
      other_item = create(:rss_feed_item)

      expect {
        post "/api/v1/rss_feeds/#{feed.feed_id}/items",
          params: { data: [ { item_id_hash: other_item.item_id_hash } ] },
          headers: service_headers, as: :json
      }.to change(feed.items, :count).by(1)

      expect(json).to eq("created" => 1)
      expect(RpgClubRssFeedItem.where(item_id_hash: other_item.item_id_hash).count).to eq(2)
    end

    it "404s for an unknown feed" do
      post "/api/v1/rss_feeds/999999999/items",
        params: { data: [ { item_id_hash: "x" } ] }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      post "/api/v1/rss_feeds/#{feed.feed_id}/items",
        params: { data: [ { item_id_hash: "x" } ] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
