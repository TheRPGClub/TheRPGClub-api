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
end
