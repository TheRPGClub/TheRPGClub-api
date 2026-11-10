# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the News Hub's backbone (spec #355, ticket #356): the
# News Hub Feature, the fixed list of News Categories, the bot recording and
# removing News Items with the service token, and the members' feed.
RSpec.describe "api/v1/news_items behavior", type: :request do
  describe "the News Hub Feature" do
    it "is a hideable Feature that reads as Preview with no stored state", feature_flags: :none do
      admin = create(:user, role_admin: true)

      get "/api/v1/features", headers: auth_headers_for(admin)

      news_hub = json.fetch("data").find { |feature| feature["key"] == "news_hub" }
      expect(news_hub).to include("name" => "News Hub", "state" => "preview", "core" => false, "hideable" => true,
        "last_change" => nil)
    end
  end

  describe "GET /api/v1/news_categories" do
    it "lists the seven News Categories in order, with key and name" do
      get "/api/v1/news_categories", headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to eq([
        { "key" => "announcements", "name" => "Announcements & Trailers", "position" => 1 },
        { "key" => "releases", "name" => "Releases & Updates", "position" => 2 },
        { "key" => "emulation", "name" => "Emulation & Preservation", "position" => 3 },
        { "key" => "industry", "name" => "Industry", "position" => 4 },
        { "key" => "hardware", "name" => "Hardware & Platforms", "position" => 5 },
        { "key" => "rumours", "name" => "Rumours & Leaks", "position" => 6 },
        { "key" => "general", "name" => "General", "position" => 7 }
      ])
    end

    it "answers the bot's service token" do
      get "/api/v1/news_categories", headers: service_headers

      expect(json.fetch("data").size).to eq(7)
    end

    it "is not found for a member while the News Hub is in Preview" do
      set_feature_flag("news_hub", "preview")

      get "/api/v1/news_categories", headers: auth_headers_for(create(:user, role_member: true))

      expect(response).to have_http_status(:not_found)
    end
  end
end
