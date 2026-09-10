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

    it "carries the scorecard in the curated shape (the listing cards render it)" do
      game = create(:game)
      create(:review, user: owner, game: game,
        facets: { "template" => "rpg", "order" => %w[story music], "scores" => { "story" => 88 } })

      get "/api/v1/games/#{game.game_id}/reviews", headers: auth_headers_for(owner)

      expect(json.dig("data", 0, "facets")).to eq(
        "template" => "rpg", "order" => %w[story music], "scores" => { "story" => 88 }
      )
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

    describe "the facets scorecard" do
      def post_facets(facets)
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 85, facets: facets } },
          headers: auth_headers_for(owner), as: :json
      end

      it "persists and reads back a valid scorecard" do
        scorecard = {
          "template" => "rpg",
          "order" => %w[story combat music],
          "scores" => { "story" => 88, "combat" => 74 }
        }

        post_facets(scorecard)

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to eq(scorecard)
        expect(UserGameReview.find(json.dig("data", "review_id")).facets).to eq(scorecard)
      end

      it "round-trips a quick take as null" do
        post_facets(nil)

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to be_nil
      end

      it "normalises an empty order to null (one representation of a quick take)" do
        post_facets({ "template" => "custom", "order" => [], "scores" => {} })

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to be_nil
      end

      it "422s on an unknown template" do
        post_facets({ "template" => "quick", "order" => %w[story] })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on an unknown facet key" do
        post_facets({ "template" => "custom", "order" => %w[story vibes] })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a duplicate key in order" do
        post_facets({ "template" => "custom", "order" => %w[story story] })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a scores key missing from order" do
        post_facets({ "template" => "custom", "order" => %w[story], "scores" => { "music" => 70 } })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a non-integer score" do
        post_facets({ "template" => "custom", "order" => %w[story], "scores" => { "story" => "88" } })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a score outside 0..100" do
        post_facets({ "template" => "custom", "order" => %w[story], "scores" => { "story" => 101 } })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on an unknown top-level key" do
        post_facets({ "template" => "rpg", "order" => %w[story], "notes" => { "story" => "fine" } })

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "the facets weighting" do
      def post_weights(weights, order: %w[story characters music])
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 85,
                            facets: { "template" => "rpg", "order" => order, "scores" => {},
                                      "weights" => weights } } },
          headers: auth_headers_for(owner), as: :json
      end

      it "persists and reads back a weighted scorecard" do
        scorecard = {
          "template" => "rpg",
          "order" => %w[story characters music],
          "scores" => { "story" => 88, "characters" => 79, "music" => 95 },
          "weights" => { "story" => 50, "characters" => 30, "music" => 20 }
        }

        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 85, facets: scorecard } },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to eq(scorecard)
        expect(UserGameReview.find(json.dig("data", "review_id")).facets).to eq(scorecard)
      end

      it "stores a plain catalogue card with no labels and no weights key at all" do
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 85,
                            facets: { "template" => "rpg", "order" => %w[story],
                                      "scores" => { "story" => 88 } } } },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to eq(
          "template" => "rpg", "order" => %w[story], "scores" => { "story" => 88 }
        )
        stored = UserGameReview.find(json.dig("data", "review_id")).facets
        expect(stored).not_to have_key("labels")
        expect(stored).not_to have_key("weights")
      end

      it "accepts a zero share (scored, but deliberately not counted)" do
        post_weights({ "story" => 100, "characters" => 0, "music" => 0 })

        expect(response).to have_http_status(:created)
      end

      it "422s when the shares sum to 99" do
        post_weights({ "story" => 50, "characters" => 30, "music" => 19 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s when the shares sum to 101" do
        post_weights({ "story" => 50, "characters" => 30, "music" => 21 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s when a facet in order has no share" do
        post_weights({ "story" => 60, "characters" => 40 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s when a share names a facet not in order" do
        post_weights({ "story" => 40, "characters" => 30, "music" => 20, "combat" => 10 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a non-integer share" do
        post_weights({ "story" => 70.5, "characters" => 19.5, "music" => 10 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a negative share" do
        post_weights({ "story" => 110, "characters" => -10, "music" => 0 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a share above 100" do
        post_weights({ "story" => 101, "characters" => 0, "music" => -1 })

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    describe "renamed and custom facets" do
      def post_card(order:, labels: nil, scores: {})
        facets = { "template" => "custom", "order" => order, "scores" => scores }
        facets["labels"] = labels unless labels.nil?

        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 85, facets: facets } },
          headers: auth_headers_for(owner), as: :json
      end

      it "persists a renamed catalogue row, keeping the key canonical" do
        post_card(order: %w[combat], labels: { "combat" => "Job System" }, scores: { "combat" => 74 })

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to include(
          "order" => %w[combat], "labels" => { "combat" => "Job System" }
        )
        expect(UserGameReview.find(json.dig("data", "review_id")).facets["labels"])
          .to eq("combat" => "Job System")
      end

      it "persists a custom row with its label" do
        post_card(order: %w[custom:1], labels: { "custom:1" => "Photo Mode" }, scores: { "custom:1" => 60 })

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "facets")).to include(
          "order" => %w[custom:1],
          "labels" => { "custom:1" => "Photo Mode" },
          "scores" => { "custom:1" => 60 }
        )
      end

      it "accepts a card mixing catalogue and custom keys" do
        post_card(order: %w[story combat custom:1],
          labels: { "combat" => "Job System", "custom:1" => "Photo Mode" },
          scores: { "story" => 88, "combat" => 74, "custom:1" => 60 })

        expect(response).to have_http_status(:created)
      end

      it "422s on a custom key with no label" do
        post_card(order: %w[story custom:1], labels: { "story" => "Plot" })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a custom key with a whitespace-only label" do
        post_card(order: %w[custom:1], labels: { "custom:1" => "   " })

        expect(response).to have_http_status(:unprocessable_content)
      end

      %w[custom:abc custom:0 custom:99999].each do |key|
        it "422s on a malformed custom key (#{key})" do
          post_card(order: [ key ], labels: { key => "Photo Mode" })

          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      it "422s on a bare invented key with no custom: prefix" do
        post_card(order: %w[photomode], labels: { "photomode" => "Photo Mode" })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a labels key that is not in order" do
        post_card(order: %w[story], labels: { "music" => "Soundtrack" })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "422s on a label longer than 40 characters" do
        post_card(order: %w[story], labels: { "story" => "x" * 41 })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "accepts a label of exactly 40 characters" do
        post_card(order: %w[story], labels: { "story" => "x" * 40 })

        expect(response).to have_http_status(:created)
      end

      it "422s on an empty label for a catalogue row" do
        post_card(order: %w[story], labels: { "story" => "" })

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "UserGameReview#facet_average" do
    it "weights the mean by the card's own split" do
      review = build(:review, facets: {
        "template" => "custom", "order" => %w[story music],
        "scores" => { "story" => 100, "music" => 0 },
        "weights" => { "story" => 75, "music" => 25 }
      })

      expect(review.facet_average).to eq(75)
    end

    it "leaves unscored facets out of the divisor" do
      review = build(:review, facets: {
        "template" => "custom", "order" => %w[story music],
        "scores" => { "story" => 80 },
        "weights" => { "story" => 20, "music" => 80 }
      })

      expect(review.facet_average).to eq(80)
    end

    it "falls back to the plain mean when every scored facet is weighted zero" do
      review = build(:review, facets: {
        "template" => "custom", "order" => %w[story music],
        "scores" => { "story" => 90, "music" => 60 },
        "weights" => { "story" => 0, "music" => 0 }
      })

      expect(review.facet_average).to eq(75)
    end

    it "takes a plain mean on an unweighted card" do
      review = build(:review, facets: {
        "template" => "rpg", "order" => %w[story combat music],
        "scores" => { "story" => 88, "combat" => 74 }
      })

      expect(review.facet_average).to eq(81)
    end

    it "is nil with no scorecard and with nothing scored" do
      expect(build(:review, facets: nil).facet_average).to be_nil
      expect(
        build(:review, facets: { "template" => "rpg", "order" => %w[story], "scores" => {} }).facet_average
      ).to be_nil
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

    it "adds a scorecard to an existing review" do
      review = create(:review, user: owner, rating: 40)
      scorecard = { "template" => "general", "order" => %w[gameplay music], "scores" => { "music" => 95 } }

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { facets: scorecard } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "facets")).to eq(scorecard)
      expect(review.reload.facets).to eq(scorecard)
    end

    it "422s on an invalid scorecard rather than storing it" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { facets: { "template" => "rpg", "order" => %w[story], "scores" => { "story" => -1 } } } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(review.reload.facets).to be_nil
    end

    it "updates a review that has no scorecard, with facets sent as null" do
      review = create(:review, user: owner, rating: 40, facets: nil)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: 55, facets: nil } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload.rating).to eq(55)
      expect(review.facets).to be_nil
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
