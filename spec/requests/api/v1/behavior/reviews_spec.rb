# frozen_string_literal: true

require "rails_helper"

# Behavior specs for the review endpoints: reads are open to any authenticated
# principal, writes are gated to the owner (or the service). A Review is a
# Draft until published (spec api#430): Drafts are readable only by their
# author and Admins, and every list covers Published Reviews only. The
# user-scoped list serves the curated ReviewEntryResource shape with the game
# embedded; the single-record endpoint returns the full record (as_json); the
# game-scoped list serves the curated ReviewUserEntryResource shape.
RSpec.describe "api/v1/reviews behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  describe "GET /api/v1/users/:user_id/reviews" do
    it "lists only that user's reviews in the curated shape with the game embedded" do
      review = create(:review, user: owner, rating: 91, title: "Peak", body: { "text" => "masterpiece" })
      create(:review, user: other_user)

      get "/api/v1/users/#{owner.user_id}/reviews", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").length).to eq(1)
      entry = json.fetch("data").first
      expect(entry).to include(
        "review_id" => review.review_id,
        "user_id" => owner.user_id,
        "gamedb_game_id" => review.gamedb_game_id,
        "rating" => 91,
        "title" => "Peak",
        "body" => { "text" => "masterpiece" }
      )
      expect(entry.fetch("game")).to include("game_id" => review.gamedb_game_id, "title" => review.game.title)
      expect(entry.fetch("published_at")).to be_present
      expect(entry.keys).not_to include("is_shared", "updated_at")
    end

    describe "Drafts" do
      let!(:published) { create(:review, user: owner) }
      let!(:draft) { create(:review, :draft, user: owner) }

      def review_ids
        json.fetch("data").map { |review| review.fetch("review_id") }
      end

      {
        "another member" => -> { auth_headers_for(create(:user)) },
        "their author" => -> { auth_headers_for(owner) },
        "an Admin" => -> { auth_headers_for(create(:user, :admin)) },
        "the service" => -> { service_headers }
      }.each do |who, headers|
        it "are left out of the list (and its count) for #{who}" do
          get "/api/v1/users/#{owner.user_id}/reviews", headers: instance_exec(&headers)

          expect(review_ids).to eq([ published.review_id ])
          expect(json.fetch("meta")).to include("count" => 1)
        end
      end
    end

    it "requires authentication" do
      get "/api/v1/users/#{owner.user_id}/reviews"

      expect(response).to have_http_status(:unauthorized)
    end

    it "lists newest published first, not newest created" do
      published_late = travel_to(3.days.ago) { create(:review, :draft, user: owner) }
      published_early = travel_to(2.days.ago) { create(:review, user: owner) }
      travel_to(1.day.ago) { published_late.publish! }

      get "/api/v1/users/#{owner.user_id}/reviews", headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |r| r.fetch("review_id") })
        .to eq([ published_late.review_id, published_early.review_id ])
    end
  end

  describe "GET /api/v1/users/:user_id/reviews/drafts" do
    def drafts_path(user = owner) = "/api/v1/users/#{user.user_id}/reviews/drafts"

    it "gives the author their Drafts, newest last-touched first, with the game and progress embedded" do
      won = create(:game, title: "Chrono Trigger")
      create(:gotm_entry, game: won)
      older = travel_to(2.days.ago) do
        create(:review, :draft, user: owner, game: won, rating: nil, title: nil, body: nil)
      end
      newer = travel_to(1.day.ago) do
        create(:review, :draft, user: owner, rating: 72, title: "Halfway", body: [ { "type" => "p" } ])
      end

      get drafts_path, headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |entry| entry.fetch("review_id") })
        .to eq([ newer.review_id, older.review_id ])
      expect(json.fetch("data").first).to include(
        "kind" => "review", "rating" => 72, "title" => "Halfway", "body" => [ { "type" => "p" } ],
        "published_at" => nil
      )
      expect(json.fetch("data").first.fetch("updated_at")).to be_present
      expect(json.fetch("data").last).to include("rating" => nil, "title" => nil, "body" => nil)
      expect(json.dig("data", 1, "game")).to include(
        "game_id" => won.game_id, "title" => "Chrono Trigger", "gotm_won" => true, "nr_gotm_won" => false
      )
      expect(json.dig("data", 1, "game")).to have_key("cover_url")
      expect(json.fetch("meta")).to include("count" => 2)
    end

    it "touching a Draft moves it to the top" do
      first = travel_to(2.days.ago) { create(:review, :draft, user: owner) }
      second = travel_to(1.day.ago) { create(:review, :draft, user: owner) }
      first.update!(title: "Back to it")

      get drafts_path, headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |entry| entry.fetch("review_id") })
        .to eq([ first.review_id, second.review_id ])
    end

    it "never lists Published Reviews, nor another member's Drafts" do
      draft = create(:review, :draft, user: owner)
      create(:review, user: owner)
      create(:review, :draft, user: other_user)

      get drafts_path, headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |entry| entry.fetch("review_id") }).to eq([ draft.review_id ])
      expect(json.fetch("meta")).to include("count" => 1)
    end

    it "lets an Admin read a member's Drafts" do
      draft = create(:review, :draft, user: owner)

      get drafts_path, headers: auth_headers_for(create(:user, :admin))

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data").map { |entry| entry.fetch("review_id") }).to eq([ draft.review_id ])
    end

    {
      "another member" => -> { auth_headers_for(create(:user)) },
      "the service" => -> { service_headers }
    }.each do |who, headers|
      it "refuses #{who}" do
        create(:review, :draft, user: owner)

        get drafts_path, headers: instance_exec(&headers)

        expect(response).to have_http_status(:forbidden)
        expect(json).to include("error" => "forbidden")
      end
    end

    it "narrows to one game's Drafts with game_id" do
      game = create(:game)
      draft = create(:review, :draft, user: owner, game: game)
      revisited = create(:review, user: owner)
      create(:review_revision, :draft, review: revisited)
      create(:review, :draft, user: owner)

      get drafts_path, params: { game_id: game.game_id }, headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |entry| entry.fetch("review_id") }).to eq([ draft.review_id ])
      expect(json.fetch("meta")).to include("count" => 1)

      get drafts_path, params: { game_id: revisited.gamedb_game_id }, headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |entry| entry.values_at("kind", "review_id") })
        .to eq([ [ "revision", revisited.review_id ] ])
    end

    it "serves the month a GOTM or NR-GOTM game won on the embedded game" do
      gotm = create(:gotm_entry, month_year: "November 2024").game
      create(:review, :draft, user: owner, game: gotm)

      get drafts_path, headers: auth_headers_for(owner)

      expect(json.dig("data", 0, "game")).to include("gotm_month_year" => "November 2024", "nr_gotm_month_year" => nil)
    end

    it "requires authentication" do
      get drafts_path

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

    it "leaves out Drafts, even for their author" do
      game = create(:game)
      published = create(:review, user: other_user, game: game)
      create(:review, :draft, user: owner, game: game)

      get "/api/v1/games/#{game.game_id}/reviews", headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |r| r.fetch("review_id") }).to eq([ published.review_id ])
      expect(json.fetch("meta")).to include("count" => 1)
    end

    it "orders each group newest published first" do
      game = create(:game)
      published_late = travel_to(3.days.ago) { create(:review, :draft, user: owner, game: game) }
      published_early = travel_to(2.days.ago) { create(:review, user: other_user, game: game) }
      travel_to(1.day.ago) { published_late.publish! }

      get "/api/v1/games/#{game.game_id}/reviews", headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |r| r.fetch("review_id") })
        .to eq([ published_late.review_id, published_early.review_id ])
    end
  end

  describe "POST /api/v1/users/:user_id/reviews" do
    let(:game) { create(:game) }
    let(:payload) do
      { data: { gamedb_game_id: game.game_id, rating: 85, body: { "text" => "great pacing" } } }
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
        "published_at" => nil
      )
      expect(json.fetch("data")).not_to have_key("is_shared")
    end

    it "creates a Draft without a score" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include("rating" => nil, "published_at" => nil)
    end

    describe "the quick take (publish: true)" do
      it "creates and publishes in one call" do
        freeze_time do
          post "/api/v1/users/#{owner.user_id}/reviews",
            params: { data: { gamedb_game_id: game.game_id, rating: 70, publish: true } },
            headers: auth_headers_for(owner), as: :json

          expect(response).to have_http_status(:created)
          expect(json.dig("data", "published_at")).to eq(Time.current.as_json)
        end

        get "/api/v1/games/#{game.game_id}/reviews", headers: auth_headers_for(other_user)
        expect(json.fetch("data").length).to eq(1)
      end

      it "refuses one without a score, creating nothing" do
        expect {
          post "/api/v1/users/#{owner.user_id}/reviews",
            params: { data: { gamedb_game_id: game.game_id, publish: true } },
            headers: auth_headers_for(owner), as: :json
        }.not_to change(UserGameReview, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("rating_required")
      end

      it "ignores a caller-sent published_at" do
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: { data: { gamedb_game_id: game.game_id, rating: 70, published_at: 1.year.ago } },
          headers: auth_headers_for(owner), as: :json

        expect(response).to have_http_status(:created)
        expect(json.dig("data", "published_at")).to be_nil
      end
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

    it "422s when rating is out of the 0..100 range" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id, rating: 150 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "422s when the user already has a Draft of the game (a Draft counts)" do
      create(:review, :draft, user: owner, game: game)

      expect {
        post "/api/v1/users/#{owner.user_id}/reviews",
          params: payload, headers: auth_headers_for(owner), as: :json
      }.not_to change(UserGameReview, :count)

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

    it "creates a review with a title" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id, rating: 85, title: "A masterpiece" } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "title")).to eq("A masterpiece")
      expect(UserGameReview.find(json.dig("data", "review_id")).title).to eq("A masterpiece")
    end

    it "422s when the title exceeds 120 characters" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id, rating: 85, title: "x" * 121 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts a title of exactly 120 characters" do
      post "/api/v1/users/#{owner.user_id}/reviews",
        params: { data: { gamedb_game_id: game.game_id, rating: 85, title: "x" * 120 } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
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

    describe "a Draft" do
      let(:draft) { create(:review, :draft, user: owner, rating: nil) }

      it "shows to its author" do
        get "/api/v1/reviews/#{draft.review_id}", headers: auth_headers_for(owner)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("review_id" => draft.review_id, "published_at" => nil)
      end

      it "shows to an Admin" do
        get "/api/v1/reviews/#{draft.review_id}", headers: auth_headers_for(create(:user, :admin))

        expect(response).to have_http_status(:ok)
      end

      it "is not found for another member" do
        get "/api/v1/reviews/#{draft.review_id}", headers: auth_headers_for(other_user)

        expect(response).to have_http_status(:not_found)
      end

      it "is not found for the service" do
        get "/api/v1/reviews/#{draft.review_id}", headers: service_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/reviews/:id/publish" do
    it "publishes the author's Draft" do
      draft = create(:review, :draft, user: owner, rating: 64)

      freeze_time do
        post "/api/v1/reviews/#{draft.review_id}/publish", headers: auth_headers_for(owner)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("review_id" => draft.review_id, "published_at" => Time.current.as_json)
      end

      get "/api/v1/users/#{owner.user_id}/reviews", headers: auth_headers_for(other_user)
      expect(json.fetch("data").map { |r| r.fetch("review_id") }).to eq([ draft.review_id ])
    end

    it "refuses a Draft without a score" do
      draft = create(:review, :draft, user: owner, rating: nil)

      post "/api/v1/reviews/#{draft.review_id}/publish", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("rating_required")
      expect(draft.reload.published_at).to be_nil
    end

    it "keeps the first publish date of an already Published Review" do
      first = 3.days.ago.change(usec: 0)
      review = create(:review, user: owner, published_at: first)

      post "/api/v1/reviews/#{review.review_id}/publish", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(review.reload.published_at).to eq(first)
    end

    it "forbids a non-owner" do
      draft = create(:review, :draft, user: owner)

      post "/api/v1/reviews/#{draft.review_id}/publish", headers: auth_headers_for(other_user)

      expect(response).to have_http_status(:forbidden)
      expect(draft.reload.published_at).to be_nil
    end

    it "404s for an unknown id (as the service)" do
      post "/api/v1/reviews/999999999/publish", headers: service_headers

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

    it "sets a title on an existing review" do
      review = create(:review, user: owner, rating: 40, title: nil)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { title: "Solid entry" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "title")).to eq("Solid entry")
      expect(review.reload.title).to eq("Solid entry")
    end

    it "leaves the title unchanged when omitted" do
      review = create(:review, user: owner, rating: 40, title: "Original title")

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: 55 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload.title).to eq("Original title")
    end

    it "clears a title back to null" do
      review = create(:review, user: owner, rating: 40, title: "Original title")

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { title: nil } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "title")).to be_nil
      expect(review.reload.title).to be_nil
    end

    it "422s on a title over 120 characters rather than storing it" do
      review = create(:review, user: owner, rating: 40, title: "Original title")

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { title: "x" * 121 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(review.reload.title).to eq("Original title")
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

    it "never unpublishes: a sent published_at is ignored" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { published_at: nil, title: "Still out" } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(review.reload.published_at).to be_present
    end

    it "refuses to clear the score of a Published Review, saying a Published take keeps it" do
      review = create(:review, user: owner, rating: 40)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: nil } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "rating_required", "message" => "A Published take must keep its score.")
      expect(review.reload.rating).to eq(40)
    end

    it "refuses clearing a locked score as score_locked" do
      review = create(:review, user: owner, rating: 40, published_at: 10.days.ago)

      patch "/api/v1/reviews/#{review.review_id}",
        params: { data: { rating: nil } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.fetch("error")).to eq("score_locked")
    end

    it "lets a Draft's score be cleared" do
      draft = create(:review, :draft, user: owner, rating: 40)

      patch "/api/v1/reviews/#{draft.review_id}",
        params: { data: { rating: nil } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(draft.reload.rating).to be_nil
    end

    # ADR 0013: an Edit may change the score only in the first 7 days after
    # publishing; title, text and scorecard stay editable forever.
    describe "the 7-day score lock" do
      let(:published_at) { Time.zone.parse("2026-11-01 12:00:00") }
      let!(:review) { create(:review, user: owner, rating: 40, title: "First", published_at: published_at) }

      def edit(data)
        patch "/api/v1/reviews/#{review.review_id}", params: { data: data }, headers: auth_headers_for(owner), as: :json
      end

      it "lets an Edit change the score on the 7th day" do
        travel_to(published_at + 7.days - 1.minute) { edit(rating: 85) }

        expect(response).to have_http_status(:ok)
        expect(review.reload.rating).to eq(85)
      end

      it "refuses an Edit that changes the score after 7 days, with score_locked" do
        travel_to(published_at + 7.days + 1.minute) { edit(rating: 85, title: "Changed my mind") }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to eq("score_locked")
        expect(review.reload).to have_attributes(rating: 40, title: "First")
      end

      it "still accepts the unchanged score alongside other fields after 7 days" do
        travel_to(published_at + 30.days) { edit(rating: 40, title: "Typo fixed") }

        expect(response).to have_http_status(:ok)
        expect(review.reload.title).to eq("Typo fixed")
      end

      it "keeps title, text and scorecard editable forever" do
        scorecard = { "template" => "general", "order" => %w[music], "scores" => { "music" => 90 } }

        travel_to(published_at + 2.years) do
          edit(title: "Years on", body: { "text" => "reworded" }, facets: scorecard)
        end

        expect(response).to have_http_status(:ok)
        expect(review.reload).to have_attributes(title: "Years on", body: { "text" => "reworded" }, facets: scorecard)
      end

      it "serves when the score locks, so the website can show it locked" do
        get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)

        expect(Time.zone.parse(json.dig("data", "score_locks_at"))).to eq(published_at + 7.days)
      end

      it "doesn't lock a Draft's score, however old the Draft" do
        draft = create(:review, :draft, user: owner, rating: 40)

        travel_to(30.days.from_now) do
          patch "/api/v1/reviews/#{draft.review_id}",
            params: { data: { rating: 70 } }, headers: auth_headers_for(owner), as: :json
        end

        expect(response).to have_http_status(:ok)
        expect(draft.reload.rating).to eq(70)
        expect(json.dig("data", "score_locks_at")).to be_nil
      end
    end

    # An Edit more than an hour after publishing marks the take as edited.
    describe "the edited marker" do
      let(:published_at) { Time.zone.parse("2026-11-01 12:00:00") }
      let!(:review) { create(:review, user: owner, rating: 40, title: "First", published_at: published_at) }

      def edit(data)
        patch "/api/v1/reviews/#{review.review_id}", params: { data: data }, headers: auth_headers_for(owner), as: :json
      end

      it "is not set by an Edit within the first hour" do
        travel_to(published_at + 59.minutes) { edit(title: "Quick fix") }

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "edited_at")).to be_nil
      end

      it "records when an Edit past the first hour was made" do
        edited_at = published_at + 3.days
        travel_to(edited_at) { edit(title: "Later fix") }

        expect(response).to have_http_status(:ok)
        expect(Time.zone.parse(json.dig("data", "edited_at"))).to eq(edited_at)
      end

      it "is not set by a save that changes nothing" do
        travel_to(published_at + 3.days) { edit(title: "First", rating: 40) }

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "edited_at")).to be_nil
      end

      it "is served in the member's reviews list" do
        travel_to(published_at + 3.days) { edit(title: "Later fix") }

        get "/api/v1/users/#{owner.user_id}/reviews", headers: auth_headers_for(other_user)

        expect(Time.zone.parse(json.dig("data", 0, "edited_at"))).to eq(published_at + 3.days)
      end

      it "is never set on a Draft, nor by publishing it" do
        draft = create(:review, :draft, user: owner, rating: 40)

        travel_to(3.days.from_now) do
          patch "/api/v1/reviews/#{draft.review_id}",
            params: { data: { title: "Still writing" } }, headers: auth_headers_for(owner), as: :json
          post "/api/v1/reviews/#{draft.review_id}/publish", headers: auth_headers_for(owner)
        end

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "edited_at")).to be_nil
      end
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

  # The Review Feed (spec api#430, ticket api#432) extends the Latest Reviews
  # Dashboard Panel's endpoint: same list, plus what a feed box needs.
  describe "GET /api/v1/reviews, the Review Feed" do
    def feed(params = {})
      get "/api/v1/reviews", params: params, headers: auth_headers_for(other_user)
      expect(response).to have_http_status(:ok)
      json.fetch("data")
    end

    it "marks each Published Review as a review entry, with no Revision fields yet" do
      review = create(:review, user: owner, rating: 80)

      entry = feed.first

      expect(entry).to include(
        "kind" => "review", "review_id" => review.review_id, "revision_id" => nil,
        "rating" => 80, "previous_rating" => nil
      )
    end

    it "marks each game with its GOTM and NR-GOTM track, as the game endpoints do" do
      gotm = create(:gotm_entry).game
      nr_gotm = create(:nr_gotm_entry).game
      gotm_review = create(:review, user: owner, game: gotm)
      nr_gotm_review = create(:review, user: owner, game: nr_gotm)
      plain_review = create(:review, user: owner)

      games = feed.to_h { |entry| [ entry.fetch("review_id"), entry.fetch("game") ] }

      expect(games.fetch(gotm_review.review_id)).to include("gotm_won" => true, "nr_gotm_won" => false)
      expect(games.fetch(nr_gotm_review.review_id)).to include("gotm_won" => false, "nr_gotm_won" => true)
      expect(games.fetch(plain_review.review_id)).to include("gotm_won" => false, "nr_gotm_won" => false,
        "title" => plain_review.game.title)
    end

    it "serves the month each GOTM or NR-GOTM game won, for the track pill" do
      gotm = create(:gotm_entry, month_year: "November 2024").game
      nr_gotm = create(:nr_gotm_entry, month_year: "March 2025").game
      gotm_review = create(:review, user: owner, game: gotm)
      nr_gotm_review = create(:review, user: owner, game: nr_gotm)
      plain_review = create(:review, user: owner)

      games = feed.to_h { |entry| [ entry.fetch("review_id"), entry.fetch("game") ] }

      expect(games.fetch(gotm_review.review_id))
        .to include("gotm_month_year" => "November 2024", "nr_gotm_month_year" => nil)
      expect(games.fetch(nr_gotm_review.review_id))
        .to include("gotm_month_year" => nil, "nr_gotm_month_year" => "March 2025")
      expect(games.fetch(plain_review.review_id)).to include("gotm_month_year" => nil, "nr_gotm_month_year" => nil)
    end

    describe "Written only" do
      def paragraph(text) = [ { "type" => "p", "children" => [ { "text" => text } ] } ]

      let!(:written) do
        {
          "an editor body" => create(:review, user: owner, body: paragraph("Loved the combat.")),
          "a legacy string" => create(:review, user: owner, body: "Plain old text"),
          "an imported summary" => create(:review, user: owner, body: { "summary" => "Imported take" })
        }
      end
      let!(:quick_takes) do
        {
          "no body" => create(:review, user: owner, body: nil),
          "an empty editor body" => create(:review, user: owner, body: paragraph("   ")),
          "a blank string" => create(:review, user: owner, body: "  "),
          "an empty object" => create(:review, user: owner, body: {})
        }
      end

      it "flags every entry with whether it has any text" do
        flags = feed.to_h { |entry| [ entry.fetch("review_id"), entry.fetch("written") ] }

        written.each_value { |review| expect(flags.fetch(review.review_id)).to be(true) }
        quick_takes.each_value { |review| expect(flags.fetch(review.review_id)).to be(false) }
      end

      it "drops the score-only quick takes with written=1" do
        entries = feed(written: 1)

        expect(entries.map { |entry| entry.fetch("review_id") }).to match_array(written.values.map(&:review_id))
        expect(json.dig("meta", "count")).to eq(3)
      end

      it "keeps every entry without it" do
        expect(feed(written: 0).length).to eq(7)
      end
    end
  end
end
