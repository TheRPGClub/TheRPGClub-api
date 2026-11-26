# frozen_string_literal: true

require "rails_helper"

# The News page's Shelves tab (spec api#494, ticket api#497): one read that
# gives, for each News Category in the member's default view, its newest News
# Items and how many were posted today (UTC).
RSpec.describe "api/v1/news_items/shelves", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user, role_member: true) }
  let(:now) { Time.utc(2026, 11, 26, 12) }

  before { travel_to now }

  def shelves(params = {}, headers = auth_headers_for(member))
    get "/api/v1/news_items/shelves", params: params, headers: headers
    expect(response).to have_http_status(:ok)
    json
  end

  def shelf(body, key) = body.fetch("data").find { |entry| entry["category_key"] == key }

  def switch_off(*keys)
    keys.each { |key| create(:member_news_category_preference, user: member, category_key: key) }
  end

  describe "shelves" do
    it "gives every News Category in News Category order, each with its name" do
      body = shelves

      expect(body.fetch("data").map { |entry| entry["category_key"] }).to eq(NewsCategory.keys)
      expect(shelf(body, "releases")["name"]).to eq("Releases & Updates")
    end

    it "holds each News Category's newest News Items, newest first, ten by default" do
      oldest = create(:news_item, category_key: "releases", posted_at: now - 20.hours)
      newer = Array.new(10) { |i| create(:news_item, category_key: "releases", posted_at: now - (10 - i).hours) }
      other = create(:news_item, category_key: "industry", posted_at: now - 1.minute)

      body = shelves

      ids = shelf(body, "releases")["items"].map { |item| item["message_id"] }
      expect(ids).to eq(newer.reverse.map(&:message_id))
      expect(ids).not_to include(oldest.message_id)
      expect(shelf(body, "industry")["items"].map { |item| item["message_id"] }).to eq([ other.message_id ])
      expect(body.dig("meta", "per")).to eq(10)
    end

    it "takes `per` items per shelf, at most twenty" do
      25.times { |i| create(:news_item, category_key: "general", posted_at: now - i.minutes) }

      expect(shelf(shelves(per: 3), "general")["items"].size).to eq(3)
      body = shelves(per: 50)
      expect(shelf(body, "general")["items"].size).to eq(20)
      expect(body.dig("meta", "per")).to eq(20)
    end

    it "breaks a tie in posting time the way the feed does" do
      first = create(:news_item, category_key: "general", posted_at: now - 1.hour)
      second = create(:news_item, category_key: "general", posted_at: now - 1.hour)

      ids = shelf(shelves(per: 1), "general")["items"].map { |item| item["message_id"] }

      expect(ids).to eq([ second.message_id ])
      expect(first.id).to be < second.id
    end

    it "serializes each News Item as the feed does, author name included" do
      author = create(:user, global_name: "Ada")
      item = create(:news_item, category_key: "hardware", author_id: author.user_id, author_name: "old name",
        link_title: "A console", comment: "neat")

      served = shelf(shelves, "hardware")["items"].first

      get "/api/v1/news_items", headers: auth_headers_for(member)
      expect(served).to eq(json.fetch("data").find { |entry| entry["message_id"] == item.message_id })
      expect(served.dig("author", "name")).to eq("Ada")
    end

    it "keeps an empty News Category, with no items and nothing today" do
      expect(shelf(shelves, "emulation")).to include("items" => [], "today_count" => 0)
    end

    it "leaves out imported News Items staff have not sorted" do
      create(:news_item, origin: "import", category_key: nil)

      expect(shelves.fetch("data").sum { |entry| entry["items"].size }).to eq(0)
    end
  end

  describe "today_count" do
    it "counts the News Items posted since the start of today, UTC, whatever the shelf shows" do
      create(:news_item, category_key: "rumours", posted_at: Time.utc(2026, 11, 25, 23, 59, 59))
      create(:news_item, category_key: "rumours", posted_at: Time.utc(2026, 11, 26, 0, 0, 0))
      create(:news_item, category_key: "rumours", posted_at: now - 1.minute)
      create(:news_item, category_key: "general", posted_at: now - 1.hour)

      body = shelves(per: 1)

      expect(shelf(body, "rumours")["today_count"]).to eq(2)
      expect(shelf(body, "general")["today_count"]).to eq(1)
      expect(shelf(body, "industry")["today_count"]).to eq(0)
    end

    it "moves on at UTC midnight" do
      create(:news_item, category_key: "rumours", posted_at: Time.utc(2026, 11, 26, 23, 0))
      travel_to Time.utc(2026, 11, 27, 0, 0, 1)

      expect(shelf(shelves, "rumours")["today_count"]).to eq(0)
    end
  end

  describe "switched-off News Categories" do
    it "leaves them out and lists them in meta.hidden_categories, in News Category order" do
      create(:news_item, category_key: "rumours")
      switch_off("general", "rumours")

      body = shelves

      expect(body.fetch("data").map { |entry| entry["category_key"] }).to eq(NewsCategory.keys - %w[rumours general])
      expect(body.dig("meta", "hidden_categories")).to eq(%w[rumours general])
    end

    it "hides nothing for the bot's service token" do
      body = shelves({}, service_headers)

      expect(body.fetch("data").size).to eq(NewsCategory.keys.size)
      expect(body.dig("meta", "hidden_categories")).to eq([])
    end
  end

  it "asks the bot to renew the expired images of the News Items it serves, as the feed does" do
    create(:news_item, category_key: "general",
      images: [ { "url" => "https://cdn.discordapp.com/attachments/1/2/a.png", "expires_at" => (now - 1.minute).iso8601 } ])

    expect { shelves }.to change(BotJob.where(kind: "news_images_renew"), :count).by(1)
    expect { shelves({}, service_headers) }.not_to change(BotJob, :count)
  end

  it "is not found for a member while the News Hub Feature is in Preview" do
    set_feature_flag("news_hub", "preview")
    get "/api/v1/news_items/shelves", headers: auth_headers_for(member)

    expect(response).to have_http_status(:not_found)
  end

  it "reads with a bounded number of queries, however many News Categories hold News Items" do
    NewsCategory.keys.each { |key| 3.times { create(:news_item, category_key: key) } }

    count_queries = lambda do
      statements = []
      track = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(track, "sql.active_record") { shelves }
      statements.count { |sql| sql.include?("news_items") }
    end

    expect(count_queries.call).to be <= 2
  end
end
