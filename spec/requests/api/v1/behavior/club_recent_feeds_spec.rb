# frozen_string_literal: true

require "rails_helper"

# The club-wide recent feeds behind the `completions_club` and `reviews`
# Dashboard Panels (spec #421, ticket #425): every member's Game Completions
# and Published Reviews, newest first, without members who have left the server.
RSpec.describe "club recent feeds", type: :request do
  let(:member) { create(:user, role_member: true) }
  let(:author) { create(:user) }

  def ids(key)
    json.fetch("data").map { |row| row.fetch(key) }
  end

  describe "GET /api/v1/completions/recent" do
    it "lists every member's completions newest first, with the member, game and platform" do
      platform = create(:platform)
      older = create(:completion, user: author, completed_at: 3.days.ago)
      newest = create(:completion, user: member, platform: platform, completed_at: 1.hour.ago)
      middle = create(:completion, user: author, completed_at: 1.day.ago)

      get "/api/v1/completions/recent", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(ids("completion_id")).to eq([ newest.completion_id, middle.completion_id, older.completion_id ])
      first = json.dig("data", 0)
      expect(first).to include("user_id" => member.user_id, "completion_type" => "Main Story")
      expect(first.fetch("user")).to include("user_id" => member.user_id, "username" => member.username)
      expect(first.fetch("game")).to include("game_id" => newest.gamedb_game_id)
      expect(first.fetch("platform")).to include("platform_id" => platform.platform_id)
    end

    it "leaves out members who have left the server" do
      departed = create(:user, server_left_at: 1.day.ago)
      kept = create(:completion, user: author)
      create(:completion, user: departed)

      get "/api/v1/completions/recent", headers: auth_headers_for(member)

      expect(ids("completion_id")).to eq([ kept.completion_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "puts undated completions last, then the latest logged first" do
      undated = create(:completion, user: author).tap { |c| c.update_column(:completed_at, nil) }
      dated = create(:completion, user: author, completed_at: 1.year.ago)

      get "/api/v1/completions/recent", headers: auth_headers_for(member)

      expect(ids("completion_id")).to eq([ dated.completion_id, undated.completion_id ])
    end

    it "honours per" do
      kept = create(:completion, user: author, completed_at: 1.hour.ago)
      create(:completion, user: author, completed_at: 2.days.ago)

      get "/api/v1/completions/recent", params: { per: 1 }, headers: auth_headers_for(member)

      expect(ids("completion_id")).to eq([ kept.completion_id ])
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "is not found for a member while Game Completions is Off" do
      set_feature_flag("game_completions", "off")

      get "/api/v1/completions/recent", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/completions/recent"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/reviews" do
    it "lists every member's Published Reviews newest published first, with the author and game" do
      older = create(:review, user: author, published_at: 2.days.ago)
      newest = create(:review, user: member, rating: 91, title: "Peak", created_at: 9.days.ago,
        published_at: 1.hour.ago)
      middle = create(:review, user: author, published_at: 1.day.ago)

      get "/api/v1/reviews", headers: auth_headers_for(member)

      expect(response).to have_http_status(:ok)
      expect(ids("review_id")).to eq([ newest.review_id, middle.review_id, older.review_id ])
      first = json.dig("data", 0)
      expect(first).to include("user_id" => member.user_id, "rating" => 91, "title" => "Peak")
      expect(first.fetch("user")).to include("user_id" => member.user_id, "username" => member.username)
      expect(first.fetch("game")).to include("game_id" => newest.gamedb_game_id)
      expect(first.keys).not_to include("is_shared", "updated_at")
    end

    it "leaves out Drafts, even for Admins and their author" do
      shared = create(:review, user: author)
      create(:review, :draft, user: author)

      [ auth_headers_for(author), auth_headers_for(create(:user, :admin)), service_headers ].each do |headers|
        get "/api/v1/reviews", headers: headers

        expect(ids("review_id")).to eq([ shared.review_id ])
      end
    end

    it "leaves out members who have left the server" do
      departed = create(:user, server_left_at: 1.day.ago)
      kept = create(:review, user: author)
      create(:review, user: departed)

      get "/api/v1/reviews", headers: auth_headers_for(member)

      expect(ids("review_id")).to eq([ kept.review_id ])
      expect(json.dig("meta", "count")).to eq(1)
    end

    it "honours per" do
      kept = create(:review, user: author, published_at: 1.hour.ago)
      create(:review, user: author, published_at: 2.days.ago)

      get "/api/v1/reviews", params: { per: 1 }, headers: auth_headers_for(member)

      expect(ids("review_id")).to eq([ kept.review_id ])
      expect(json.dig("meta", "count")).to eq(2)
    end

    it "is not found for a member while Reviews is Off" do
      set_feature_flag("reviews", "off")

      get "/api/v1/reviews", headers: auth_headers_for(member)

      expect(response).to have_http_status(:not_found)
    end

    it "requires authentication" do
      get "/api/v1/reviews"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
