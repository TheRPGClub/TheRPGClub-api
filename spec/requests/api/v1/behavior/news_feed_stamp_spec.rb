# frozen_string_literal: true

require "rails_helper"

# The News Feed Stamp: an open News page polls it and reloads the feed when
# it changes. The poll must never reach Postgres, so Neon can sleep while a
# page sits open.
RSpec.describe "api/v1/news_items/stamp behavior", type: :request do
  let(:member) { create(:user, role_member: true) }

  # Each example starts as a fresh machine: no stamp file.
  before { FileUtils.rm_f(NewsItem::FeedStamp.path) }

  # Postgres statements the block runs (the stamp is raw SQLite, so it never
  # shows up here).
  def postgres_queries
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def stamp(headers: {})
    get "/api/v1/news_items/stamp", headers: headers
    json.dig("data", "stamp")
  end

  def record(message_id)
    put "/api/v1/news_items/#{message_id}", headers: service_headers, as: :json, params: { data: {
      channel_id: "1100000000000000001", category_key: "releases", author_id: "2200000000000000002",
      author_name: "Ada", posted_at: "2026-11-09T18:30:00Z", link: { url: "https://example.test/a" }
    } }
  end

  it "answers anyone with a stamp that stays put while nothing changes" do
    first = stamp

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(first).to match(/\A\d+\z/)
    expect(stamp).to eq(first)
  end

  it "makes no Postgres queries, even with a member's session or the News Hub off" do
    headers = auth_headers_for(member)
    set_feature_flag("news_hub", "off")
    stamp

    queries = postgres_queries { stamp(headers: headers) }

    expect(response).to have_http_status(:ok)
    expect(queries).to be_empty
  end

  it "changes when a News Item is recorded, edited, recategorised or removed" do
    seen = [ stamp ]
    record("1300000000000000001")
    seen << stamp
    record("1300000000000000001")
    seen << stamp
    NewsItem.find_by!(message_id: "1300000000000000001").change_category!("industry", by: member.user_id)
    seen << stamp
    delete "/api/v1/news_items/1300000000000000001", headers: service_headers
    seen << stamp

    expect(seen.uniq.size).to eq(5)
  end
end
