# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the review endpoints: reads are open to any authenticated
# principal, writes are gated to the owner (or the service). The user-scoped
# list and single-record endpoints return the full record (as_json); the
# game-scoped list serves the curated ReviewUserEntryResource shape.
RSpec.describe "api/v1/reviews behavior", type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/reviews" do
    it "lists only that user's reviews as full records" do
      review = create(:review, user: owner, rating: 91, body: { "text" => "masterpiece" })
      create(:review, user: other_user)

      get "/api/v1/users/#{owner.user_id}/reviews", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      expect(json.fetch("data").first).to include(
        "review_id" => review.review_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => review.gamedb_game_id,
        "rating" => 91,
        "body" => { "text" => "masterpiece" },
        "is_shared" => true
      )
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/reviews"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/games/:id/reviews" do
    it "lists a game's reviews with the author embedded, body-carrying reviews first" do
      game = create(:game)
      bodyless = create(:review, user: owner, game: game, body: nil)
      with_body = create(:review, user: other_user, game: game, body: { "text" => "solid" })
      create(:review, user: owner)

      get "/api/v1/games/#{game.game_id}/reviews", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |r| r.fetch("review_id") })
        .to eq([ with_body.review_id, bodyless.review_id ])
      expect(json.fetch("data").first).to include("rating" => with_body.rating)
      expect(json.dig("data", 0, "user")).to include("user_id" => other_user.user_id)
    end

    it "does not expose the write-only is_shared flag in the curated shape" do
      game = create(:game)
      create(:review, user: owner, game: game)

      get "/api/v1/games/#{game.game_id}/reviews", headers: service_headers

      expect(json.fetch("data").first).not_to have_key("is_shared")
    end
  end

  describe "POST /api/v1/users/:user_id/reviews" do
    let(:game) { create(:game) }
    let(:payload) do
      { data: { gamedb_game_id: game.game_id, rating: 85, body: { "text" => "great pacing" }, is_shared: false } }
    end

    it "creates a review for the owner, round-tripping the JSON body" do
      expect {
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.to change(UserGameReview.where(user_id: owner.user_id), :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "user_id" => owner.user_id,
        "gamedb_game_id" => game.game_id,
        "rating" => 85,
        "body" => { "text" => "great pacing" },
        "is_shared" => false
      )
    end

    it "allows the service to write on behalf of a user" do
      post "/api/v1/users/#{owner.user_id}/reviews", params: payload, headers: service_headers, as: :json

      expect(response).to have_http_status(:created)
    end

    it "forbids another user" do
      expect {
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: payload, headers: auth_headers_for(other_user), as: :json
      }.not_to change(UserGameReview, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "422s when rating is missing" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when rating is out of the 0..100 range" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id, rating: 150 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when the user already reviewed the game (unique per user and game)" do
      create(:review, user: owner, game: game)

      expect {
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(UserGameReview, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s for an unknown game id" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: 999_999_999, rating: 50 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "400s when the data envelope is missing" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { gamedb_game_id: game.game_id, rating: 50 }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "requires authentication" do
      post "/api/v1/users/#{owner.user_id}/reviews", params: payload, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/reviews/:id" do
    it "shows a review to any authenticated user" do
      review = create(:review, user: owner)

      get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("review_id" => review.review_id, "rating" => review.rating)
    end

    it "404s for an unknown id" do
      get "/api/v1/reviews/999999999", headers: service_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /api/v1/reviews/:id" do
    it "updates the owner's review" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: 95 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "rating")).to eq(95)
      expect(review.reload.rating).to eq(95)
    end

    it "allows the service" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: 60 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload.rating).to eq(60)
    end

    it "forbids a non-owner" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: 1 } }, headers: auth_headers_for(other_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(review.reload.rating).to eq(40)
    end

    it "404s for an unknown id (as the service)" do
      patch "/api/v1/reviews/999999999",
        params: { data: { rating: 50 } }, headers: service_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/reviews/:id" do
    it "deletes the owner's review" do
      review = create(:review, user: owner)

      delete "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json).to eq("deleted" => true)
      expect(UserGameReview.exists?(review.review_id)).to be(false)
    end

    it "forbids a non-owner" do
      review = create(:review, user: owner)

      delete "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(UserGameReview.exists?(review.review_id)).to be(true)
    end
  end
end
