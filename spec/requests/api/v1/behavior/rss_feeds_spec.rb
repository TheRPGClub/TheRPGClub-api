# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the RSS feed registry endpoints: full CRUD, open to any
# authenticated caller (the bot manages feeds through the service token).
RSpec.describe "api/v1/rss_feeds behavior", type: :request do
  describe "GET /api/v1/rss_feeds" do
    it "lists feeds ordered by feed_name with the documented fields" do
      last = create(:rss_feed, feed_name: "zz feed #{SecureRandom.hex(4)}")
      first = create(:rss_feed, feed_name: "aa feed #{SecureRandom.hex(4)}")

      get "/api/v1/rss_feeds", headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:ok)
      names = json.fetch("data").map { |f| f.fetch("feed_name") }
      expect(names.index(first.feed_name)).to be < names.index(last.feed_name)
      body = json.fetch("data").find { |f| f["feed_id"] == first.feed_id }
      expect(body).to include(
        "feed_name" => first.feed_name,
        "feed_url" => first.feed_url,
        "channel_id" => first.channel_id,
        "include_keywords" => nil,
        "exclude_keywords" => nil
      )
      expect(json.fetch("meta")).to include("page" => 1)
    end

    it "requires authentication" do
      get "/api/v1/rss_feeds"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/rss_feeds/:id" do
    it "returns the feed" do
      feed = create(:rss_feed)

      get "/api/v1/rss_feeds/#{feed.feed_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("feed_id" => feed.feed_id, "feed_url" => feed.feed_url)
    end

    it "404s for an unknown id" do
      get "/api/v1/rss_feeds/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/rss_feeds" do
    let(:payload) do
      { data: { feed_name: "RPG News", feed_url: "https://example.com/rpg.rss", channel_id: "123456",
        include_keywords: "rpg,jrpg" } }
    end

    it "creates a feed for any authenticated caller" do
      expect {
        post "/api/v1/rss_feeds", params: payload, headers: auth_headers_for(create(:user)), as: :json
      }.to change(RpgClubRssFeed, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "feed_name" => "RPG News",
        "feed_url" => "https://example.com/rpg.rss",
        "channel_id" => "123456",
        "include_keywords" => "rpg,jrpg"
      )
      expect(json.dig("data", "feed_id")).to be_present
    end

    it "422s when feed_url is missing" do
      post "/api/v1/rss_feeds",
        params: { data: { feed_name: "No URL", channel_id: "123456" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Feed url")
    end

    it "creates a feed without a feed_name (documented as optional)" do
      pending "possible bug: the docs mark feed_name optional/nullable (required: feed_url, " \
        "channel_id only) but RpgClubRssFeed validates feed_name presence, so the request 422s"

      post "/api/v1/rss_feeds",
        params: { data: { feed_url: "https://example.com/noname.rss", channel_id: "123456" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    # #269: two identical Humble Bundle feeds had been posting into the same channel.
    it "422s on a second feed with the same url in the same channel and inserts nothing" do
      existing = create(:rss_feed)

      expect {
        post "/api/v1/rss_feeds",
          params: { data: { feed_name: "Dupe", feed_url: existing.feed_url, channel_id: existing.channel_id } },
          headers: service_headers, as: :json
      }.not_to change(RpgClubRssFeed, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Feed url has already been taken")
    end

    it "treats a url that only differs by surrounding whitespace as a duplicate" do
      existing = create(:rss_feed)

      expect {
        post "/api/v1/rss_feeds",
          params: { data: { feed_name: "Dupe", feed_url: "  #{existing.feed_url} ", channel_id: existing.channel_id } },
          headers: service_headers, as: :json
      }.not_to change(RpgClubRssFeed, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows the same url in a different channel" do
      existing = create(:rss_feed)

      post "/api/v1/rss_feeds",
        params: { data: { feed_name: "Elsewhere", feed_url: existing.feed_url, channel_id: "999" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/rss_feeds", params: { feed_url: "https://example.com/x.rss" },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/rss_feeds", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/rss_feeds/:id" do
    it "partially updates the feed" do
      feed = create(:rss_feed)

      patch "/api/v1/rss_feeds/#{feed.feed_id}",
        params: { data: { feed_name: "renamed feed", exclude_keywords: "gacha" } },
        headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("feed_name" => "renamed feed", "exclude_keywords" => "gacha")
      expect(feed.reload.feed_name).to eq("renamed feed")
      expect(feed.exclude_keywords).to eq("gacha")
    end

    it "supports PUT as an alias" do
      feed = create(:rss_feed)

      put "/api/v1/rss_feeds/#{feed.feed_id}",
        params: { data: { feed_name: "via put" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(feed.reload.feed_name).to eq("via put")
    end

    it "422s when blanking a required column" do
      feed = create(:rss_feed)

      patch "/api/v1/rss_feeds/#{feed.feed_id}",
        params: { data: { feed_url: "" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(feed.reload.feed_url).to be_present
    end

    it "422s when moving a feed onto a url + channel another feed already has" do
      existing = create(:rss_feed)
      feed = create(:rss_feed, channel_id: existing.channel_id)

      patch "/api/v1/rss_feeds/#{feed.feed_id}",
        params: { data: { feed_url: existing.feed_url } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to include("Feed url has already been taken")
      expect(feed.reload.feed_url).not_to eq(existing.feed_url)
    end

    it "404s for an unknown id" do
      patch "/api/v1/rss_feeds/999999999",
        params: { data: { feed_name: "nope" } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/rss_feeds/:id" do
    it "deletes the feed" do
      feed = create(:rss_feed)

      delete "/api/v1/rss_feeds/#{feed.feed_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(RpgClubRssFeed.exists?(feed.feed_id)).to be(false)
    end

    # #269: the seen-item rows used to block the delete with a raw
    # PG::ForeignKeyViolation, so a feed that had ever polled could not be removed.
    it "deletes a feed that has seen items, along with only its own items" do
      feed = create(:rss_feed)
      create_list(:rss_feed_item, 2, feed: feed)
      other_item = create(:rss_feed_item)

      delete "/api/v1/rss_feeds/#{feed.feed_id}", headers: service_headers

      expect(response).to have_http_status(:ok)
      expect(RpgClubRssFeed.exists?(feed.feed_id)).to be(false)
      expect(RpgClubRssFeedItem.where(feed_id: feed.feed_id)).to be_empty
      expect(RpgClubRssFeedItem.exists?(feed_id: other_item.feed_id, item_id_hash: other_item.item_id_hash)).to be(true)
    end

    it "404s for an unknown id" do
      delete "/api/v1/rss_feeds/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
