# frozen_string_literal: true

require "rails_helper"

# The Catch-up view's reads of the feed (spec api#494, ticket api#496, and
# the code-review fix pass): `since` and `until` bound `listed_at` (when the
# News Item was listed, not when it was posted) so the page can list the
# News Items new since the member's News Mark and the ones already seen, and
# `meta` carries the News Mark (or the `mark` the page asked with) with how
# many News Items in the same view are new.
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

  # A News Item posted at `at` and listed at `listed` (by default as soon as
  # it was posted; never for an unsorted import).
  def item(at, listed: at, **attrs)
    listed = nil if attrs.key?(:category_key) && attrs[:category_key].nil?
    create(:news_item, posted_at: at, listed_at: listed, **attrs)
  end

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

    it "since keeps a News Item listed after it though posted before it (recorded late)" do
      late = item(mark - 1.day, listed: mark + 2.hours)

      expect(feed_ids(since: mark.iso8601(3))).to eq([ fresh.message_id, late.message_id ])
    end

    it "until leaves out a News Item listed after it though posted before it, so Seen is exactly the rest" do
      item(mark - 1.day, listed: mark + 2.hours)

      expect(feed_ids(until: mark.iso8601(3))).to eq([ at_mark.message_id, old.message_id ])
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

    [ "yesterday", "2026-13-01T00:00:00Z", "1732650000", "2026-11-24T21:40:00", "2026-11-24" ].each do |bad|
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

    it "count the News Items listed after the News Mark, keyed by every News Category in order" do
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

    it "count a News Item listed after the News Mark though posted before it (recorded late)" do
      set_mark
      item(mark - 1.day, listed: mark + 1.hour, category_key: "industry")
      item(mark + 1.hour, listed: mark, category_key: "general")

      body = feed.fetch("meta")

      expect(body.fetch("new_count")).to eq(1)
      expect(body.fetch("new_category_counts")).to eq(new_counts(industry: 1))
    end

    it "count imported News Items only when listed after the News Mark" do
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

  describe "mark" do
    let(:visit_mark) { mark - 1.day }

    before do
      item(visit_mark - 1.hour, category_key: "general")
      item(visit_mark + 1.hour, category_key: "releases")
      item(mark + 1.hour, category_key: "industry")
    end

    it "counts against the given mark instead of the stored News Mark, and leaves the stored one alone" do
      set_mark

      body = feed(mark: visit_mark.iso8601(3)).fetch("meta")

      expect(body).to include("news_mark" => "2026-11-23T21:40:00.123000Z", "new_count" => 2)
      expect(body.fetch("new_category_counts")).to eq(new_counts(releases: 1, industry: 1))
      expect(NewsMark.for(member.user_id)).to eq(mark)
    end

    it "counts for a member with no stored News Mark, and stores none" do
      expect(feed(mark: visit_mark.iso8601(3)).dig("meta", "new_count")).to eq(2)
      expect(NewsMark.for(member.user_id)).to be_nil
    end

    it "takes any offset and answers in UTC" do
      expect(feed(mark: "2026-11-24T00:40:00.123+03:00").dig("meta", "news_mark")).to eq("2026-11-23T21:40:00.123000Z")
    end

    [ "soon", "2026-11-23T21:40:00", "1732650000" ].each do |bad|
      it "is a 400 for a bad mark (#{bad})" do
        get "/api/v1/news_items", params: { mark: bad }, headers: auth_headers_for(member)

        expect(response).to have_http_status(:bad_request)
        expect(json.fetch("error")).to eq("mark must be an ISO 8601 instant")
      end
    end
  end

  describe "past page one" do
    before do
      set_mark
      3.times { item(mark + 1.hour, category_key: "releases") }
    end

    it "leaves the new counts null, so later pages skip that query" do
      body = feed(page: 2, per: 2).fetch("meta")

      expect(body).to include("page" => 2, "new_count" => nil, "new_category_counts" => nil)
      expect(body.fetch("news_mark")).to eq("2026-11-24T21:40:00.123000Z")
    end

    it "counts when a mark is given" do
      expect(feed(page: 2, per: 2, mark: mark.iso8601(3)).dig("meta", "new_count")).to eq(3)
    end
  end

  it "serves listed_at on each News Item, in UTC with microseconds" do
    item(mark - 1.day, listed: Time.zone.parse("2026-11-25 08:00:00.654321 UTC"))

    expect(feed.fetch("data").first.fetch("listed_at")).to eq("2026-11-25T08:00:00.654321Z")
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
