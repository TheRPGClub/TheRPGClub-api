# frozen_string_literal: true

require "rails_helper"

# What the News page's category rail reads from the feed (spec #355, ticket
# #357): how many News Items each News Category holds for the current search,
# whatever categories the request narrows to or the member switched off, and
# which News Categories the member switched off.
RSpec.describe "api/v1/news_items category counts", type: :request do
  let(:member) { create(:user, role_member: true) }

  def meta(params = {}, headers = auth_headers_for(member))
    get "/api/v1/news_items", params: params, headers: headers
    expect(response).to have_http_status(:ok)
    json.fetch("meta")
  end

  def counts(**overrides) = NewsCategory.keys.index_with(0).merge(overrides.transform_keys(&:to_s))

  def switch_off(*keys)
    keys.each { |key| create(:member_news_category_preference, user: member, category_key: key) }
  end

  describe "meta.category_counts" do
    it "counts every News Category, in order, with zeros for the empty ones" do
      2.times { create(:news_item, category_key: "releases") }
      create(:news_item, category_key: "general")

      body = meta

      expect(body.fetch("category_counts")).to eq(counts(releases: 2, general: 1))
      expect(body.fetch("category_counts").keys).to eq(NewsCategory.keys)
    end

    it "counts only News Items that have a News Category" do
      create(:news_item, category_key: "industry")
      create(:news_item, origin: "import", category_key: nil)

      expect(meta.fetch("category_counts")).to eq(counts(industry: 1))
    end

    it "counts over the current search" do
      create(:news_item, category_key: "releases", link_title: "Zelda dated")
      create(:news_item, category_key: "rumours", comment: "zelda remake?")
      create(:news_item, category_key: "releases", link_title: "Mario dated")

      expect(meta(q: "zelda").fetch("category_counts")).to eq(counts(releases: 1, rumours: 1))
    end

    it "ignores the category filter, so every News Category shows its count" do
      create(:news_item, category_key: "releases")
      create(:news_item, category_key: "rumours")

      body = meta(category: "releases")

      expect(body.fetch("count")).to eq(1)
      expect(body.fetch("category_counts")).to eq(counts(releases: 1, rumours: 1))
    end

    it "ignores the member's News Category Preferences, so a switched-off category shows its count" do
      create(:news_item, category_key: "releases")
      create(:news_item, category_key: "rumours")
      switch_off("rumours")

      body = meta

      expect(body.fetch("count")).to eq(1)
      expect(body.fetch("category_counts")).to eq(counts(releases: 1, rumours: 1))
    end
  end

  describe "meta.hidden_categories" do
    it "lists the News Categories the member switched off, in News Category order" do
      switch_off("general", "rumours")

      expect(meta.fetch("hidden_categories")).to eq(%w[rumours general])
    end

    it "is the same whatever the request filters by" do
      switch_off("rumours")

      expect(meta(category: "rumours", q: "x").fetch("hidden_categories")).to eq(%w[rumours])
    end

    it "is empty when the member switched nothing off, and for the bot's service token" do
      expect(meta.fetch("hidden_categories")).to eq([])

      switch_off("rumours")
      expect(meta({}, service_headers).fetch("hidden_categories")).to eq([])
    end
  end
end
