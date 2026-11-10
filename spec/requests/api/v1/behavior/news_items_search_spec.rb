# frozen_string_literal: true

require "rails_helper"

# Searching the News Hub feed (spec #355, ticket #357): `q` matches a News
# Item's link title and comment, case-insensitively, and narrows whatever the
# rest of the request asks for.
RSpec.describe "api/v1/news_items search", type: :request do
  let(:member) { create(:user, role_member: true) }

  def news_item(title: nil, comment: nil, **attrs)
    create(:news_item, link_title: title, comment: comment, **attrs)
  end

  def feed(params = {})
    get "/api/v1/news_items", params: params, headers: auth_headers_for(member)
    expect(response).to have_http_status(:ok)
    json
  end

  def feed_ids(params = {}) = feed(params).fetch("data").map { |item| item.fetch("message_id") }

  it "matches the link title, whatever the case" do
    hit = news_item(title: "Elden Ring 2 announced")
    news_item(title: "Zelda remaster dated")

    expect(feed_ids(q: "elden RING")).to eq([ hit.message_id ])
  end

  it "matches the member's comment, so an image-only News Item can be found" do
    hit = create(:news_item, link_url: nil, comment: "Leaked box art for the new Persona",
      images: [ { "url" => "https://cdn.discordapp.com/attachments/1/2/a.png", "expires_at" => 1.day.from_now.iso8601 } ])
    news_item(title: "Metaphor sales", comment: "Atlus is busy")

    expect(feed_ids(q: "persona")).to eq([ hit.message_id ])
  end

  it "matches part of a word" do
    hit = news_item(title: "Emulator update: Dolphin 2611")

    expect(feed_ids(q: "dolph")).to eq([ hit.message_id ])
  end

  it "takes % and _ literally" do
    hit = news_item(title: "Sale: 50% off")
    news_item(title: "Sale: 500 games")

    expect(feed_ids(q: "50%")).to eq([ hit.message_id ])
    expect(feed_ids(q: "_")).to eq([])
  end

  it "combines with the News Category filter" do
    hit = news_item(title: "Switch 2 price", category_key: "hardware")
    news_item(title: "Switch 2 sales", category_key: "industry")
    news_item(title: "Steam Deck 2", category_key: "hardware")

    expect(feed_ids(q: "switch", category: "hardware")).to eq([ hit.message_id ])
  end

  it "counts only the matches in the page meta" do
    3.times { |i| news_item(title: "Zelda news #{i}", posted_at: i.days.ago) }
    news_item(title: "Mario news")

    body = feed(q: "zelda", per: 2)

    expect(body.fetch("data").size).to eq(2)
    expect(body.fetch("meta")).to include("count" => 3, "pages" => 2, "next" => 2)
  end

  it "never finds a News Item that has no News Category" do
    create(:news_item, origin: "import", category_key: nil, link_title: "Unsorted Zelda news")

    expect(feed_ids(q: "zelda")).to eq([])
  end

  it "ignores a blank search" do
    news_item(title: "One")
    news_item(title: "Two")

    expect(feed(q: "  ").dig("meta", "count")).to eq(2)
  end
end
