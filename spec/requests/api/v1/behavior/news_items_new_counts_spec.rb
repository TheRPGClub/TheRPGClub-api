# frozen_string_literal: true

require "rails_helper"

# The Catch-up view's reads of the feed (spec api#494, ticket api#496):
# `since` and `until` bound `posted_at` so the page can list the News Items
# new since the member's News Mark and the ones already seen, and `meta`
# carries the News Mark with how many News Items in the same view are new.
RSpec.describe "api/v1/news_items since, until and new counts", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:now) { Time.zone.parse("2026-11-26 18:00:00 UTC") }
  let(:mark) { Time.zone.parse("2026-11-24 21:40:00.123 UTC") }

  around { |example| travel_to(now) { example.run } }

  def feed(params = {}, headers = auth_headers_for(member))
    get "/api/v1/news_items", params: params, headers: headers
    expect(response).to have_http_status(:ok)
    json
  end

  def feed_ids(params = {}) = feed(params).fetch("data").map { |item| item.fetch("message_id") }

  def new_counts(**overrides) = NewsCategory.keys.index_with(0).merge(overrides.transform_keys(&:to_s))

  def set_mark(instant = mark) = NewsMark.advance!(member.user_id, instant, now: now)

  def switch_off(*keys)
    keys.each { |key| create(:member_news_category_preference, user: member, category_key: key) }
  end

  def item(at, **attrs) = create(:news_item, posted_at: at, **attrs)

  describe "since and until" do
    let!(:old) { item(mark - 2.days) }
    let!(:at_mark) { item(mark) }
    let!(:fresh) { item(mark + 1.hour) }

    it "since keeps the News Items posted after it" do
      expect(feed_ids(since: mark.iso8601(3))).to eq([ fresh.message_id ])
    end

    it "until keeps the News Items posted at or before it" do
      expect(feed_ids(until: mark.iso8601(3))).to eq([ at_mark.message_id, old.message_id ])
    end

    it "since and until together keep the News Items between them" do
      expect(feed_ids(since: (mark - 3.days).iso8601, until: (mark - 1.hour).iso8601)).to eq([ old.message_id ])
    end

    it "accepts any ISO 8601 offset" do
      expect(feed_ids(since: "2026-11-25T00:40:00.123+03:00")).to eq([ fresh.message_id ])
    end

    it "pages and counts only the News Items in bounds" do
      expect(feed(until: mark.iso8601(3)).fetch("meta")).to include("count" => 2)
    end

    it "combines with the News Category filter and the search" do
      hit = item(mark + 2.hours, category_key: "hardware", link_title: "Switch 2 price")
      item(mark + 2.hours, category_key: "industry", link_title: "Switch 2 sales")
      item(mark - 1.hour, category_key: "hardware", link_title: "Switch 2 rumour")

      expect(feed_ids(since: mark.iso8601(3), category: "hardware", q: "switch")).to eq([ hit.message_id ])
    end

    it "combines with the default view, leaving out switched-off News Categories" do
      item(mark + 2.hours, category_key: "rumours")
      switch_off("rumours")

      expect(feed_ids(since: mark.iso8601(3))).to eq([ fresh.message_id ])
    end

    it "ignores a blank value" do
      expect(feed_ids(since: "", until: " ").size).to eq(3)
    end

    [ "yesterday", "2026-13-01T00:00:00Z", "1732650000" ].each do |bad|
      it "is a 400 for a bad since (#{bad})" do
        get "/api/v1/news_items", params: { since: bad }, headers: auth_headers_for(member)

        expect(response).to have_http_status(:bad_request)
        expect(json.fetch("error")).to include("since")
      end
    end

    it "is a 400 for a bad until" do
      get "/api/v1/news_items", params: { until: "soon" }, headers: auth_headers_for(member)

      expect(response).to have_http_status(:bad_request)
      expect(json.fetch("error")).to include("until")
    end
  end

  describe "meta.news_mark" do
    it "is null when the member has no News Mark" do
      expect(feed.dig("meta", "news_mark")).to be_nil
    end

    it "is the member's News Mark, as the News Mark endpoint serves it" do
      set_mark

      expect(feed.dig("meta", "news_mark")).to eq("2026-11-24T21:40:00.123000Z")
    end

    it "is null for the bot's service token" do
      set_mark

      expect(feed({}, service_headers).dig("meta", "news_mark")).to be_nil
    end
  end

  describe "meta.new_count and meta.new_category_counts" do
    it "are 0 when the member has no News Mark" do
      item(now - 1.minute, category_key: "releases")

      body = feed.fetch("meta")

      expect(body.fetch("new_count")).to eq(0)
      expect(body.fetch("new_category_counts")).to eq(new_counts)
    end

    it "count the News Items posted after the News Mark, keyed by every News Category in order" do
      set_mark
      2.times { item(mark + 1.hour, category_key: "releases") }
      item(mark + 2.hours, category_key: "rumours")
      item(mark, category_key: "releases")
      item(mark - 1.day, category_key: "general")

      body = feed.fetch("meta")

      expect(body.fetch("new_count")).to eq(3)
      expect(body.fetch("new_category_counts")).to eq(new_counts(releases: 2, rumours: 1))
      expect(body.fetch("new_category_counts").keys).to eq(NewsCategory.keys)
    end

    it "leave out switched-off News Categories in the default view" do
      set_mark
      item(mark + 1.hour, category_key: "releases")
      item(mark + 1.hour, category_key: "rumours")
      switch_off("rumours")

      body = feed.fetch("meta")

      expect(body.fetch("new_count")).to eq(1)
      expect(body.fetch("new_category_counts")).to eq(new_counts(releases: 1))
    end

    it "follow the asked News Categories, switched off or not" do
      set_mark
      item(mark + 1.hour, category_key: "releases")
      item(mark + 1.hour, category_key: "rumours")
      switch_off("rumours")

      body = feed(category: "rumours").fetch("meta")

      expect(body.fetch("new_count")).to eq(1)
      expect(body.fetch("new_category_counts")).to eq(new_counts(rumours: 1))
    end

    it "follow the search" do
      set_mark
      item(mark + 1.hour, category_key: "releases", link_title: "Zelda dated")
      item(mark + 1.hour, category_key: "industry", link_title: "Mario sales")

      expect(feed(q: "zelda").dig("meta", "new_count")).to eq(1)
    end

    it "ignore since and until, so the seen list still shows how many are new" do
      set_mark
      item(mark + 1.hour)
      item(mark - 1.hour)

      body = feed(until: mark.iso8601(3)).fetch("meta")

      expect(body.fetch("count")).to eq(1)
      expect(body.fetch("new_count")).to eq(1)
    end

    it "count imported News Items only when posted after the News Mark" do
      set_mark
      item(mark - 1.year, origin: "import", category_key: "general")
      late = item(mark + 1.hour, origin: "import", category_key: "general")
      item(mark + 1.hour, origin: "import", category_key: nil)

      body = feed.fetch("meta")

      expect(late).to be_persisted
      expect(body.fetch("new_count")).to eq(1)
      expect(body.fetch("new_category_counts")).to eq(new_counts(general: 1))
    end

    it "are 0 for the bot's service token" do
      item(now - 1.minute)

      body = feed({}, service_headers).fetch("meta")

      expect(body.fetch("new_count")).to eq(0)
      expect(body.fetch("new_category_counts")).to eq(new_counts)
    end
  end

  it "reads the new counts in one grouped query, whatever the number of News Items" do
    set_mark
    NewsCategory.keys.each { |key| 3.times { item(mark + 1.hour, category_key: key) } }

    statements = []
    track = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(track, "sql.active_record") { feed }
    news_reads = statements.select { |sql| sql.include?("news_items") }

    expect(news_reads.count { |sql| sql.include?("GROUP BY") && sql.include?(">") }).to eq(1)
    # The page, its count, the category rail and the new counts.
    expect(news_reads.size).to be <= 4
  end
end
