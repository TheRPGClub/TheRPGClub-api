# frozen_string_literal: true

require "rails_helper"

# Behavior specs for Revisions (spec api#430, ticket #433): dated returns to
# a Published Review. A Revision is a Draft until its author publishes it;
# the latest Published Revision's score is the Review's current score.
RSpec.describe "api/v1 review revisions behavior", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:owner) { create(:user) }
  let(:review) { create(:review, user: owner, rating: 72) }

  def revisions_path(target = review) = "/api/v1/reviews/#{target.review_id}/revisions"

  describe "POST /api/v1/reviews/:id/revisions (Revisit)" do
    it "starts a Draft Revision of the author's Published Review" do
      post revisions_path, params: { data: { title: "Second run", body: { "text" => "kinder now" } } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(json.fetch("data")).to include(
        "review_id" => review.review_id, "rating" => nil, "title" => "Second run",
        "body" => { "text" => "kinder now" }, "published_at" => nil, "previous_rating" => 72
      )
      expect(json.dig("data", "revision_id")).to be_a(Integer)
    end
  end

  describe "Revisit refusals" do
    it "refuses a Revision of a Draft Review" do
      draft = create(:review, :draft, user: owner)

      post revisions_path(draft), params: { data: {} }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "review_not_published")
    end

    it "allows one Draft Revision per Review at a time" do
      create(:review_revision, :draft, review: review)

      post revisions_path, params: { data: {} }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "draft_revision_exists")
    end

    it "answers a lost race for the one Draft Revision with draft_revision_exists" do
      allow_any_instance_of(UserGameReviewRevision).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

      post revisions_path, params: { data: {} }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "draft_revision_exists")
    end

    it "allows a new Draft Revision once the last one is Published" do
      create(:review_revision, review: review)

      post revisions_path, params: { data: {} }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:created)
    end

    it "refuses another member" do
      post revisions_path, params: { data: {} }, headers: auth_headers_for(create(:user)), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "a Draft Revision" do
    let(:revision) { create(:review_revision, :draft, review: review) }

    def revision_path(suffix = "") = "/api/v1/review_revisions/#{revision.revision_id}#{suffix}"

    it "autosaves, staying a Draft and leaving the Review's score alone" do
      patch revision_path, params: { data: { rating: 60, title: "Draft one" } },
        headers: auth_headers_for(owner), as: :json
      patch revision_path, params: { data: { rating: 85 } }, headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("rating" => 85, "title" => "Draft one", "published_at" => nil)

      get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)
      expect(json.fetch("data")).to include("rating" => 72, "revisions" => [])
    end

    it "is refused publishing without a score" do
      post revision_path("/publish"), headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "rating_required")
    end

    it "validates its scorecard like a Review's" do
      patch revision_path, params: { data: { facets: { "template" => "rpg", "order" => %w[nonsense] } } },
        headers: auth_headers_for(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is refused to another member" do
      patch revision_path, params: { data: { title: "mine now" } }, headers: auth_headers_for(create(:user)),
        as: :json

      expect(response).to have_http_status(:forbidden)
    end

    describe "visibility" do
      before { revision }

      it "is served to its author on the Review and in its revisions" do
        get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)
        expect(json.dig("data", "draft_revision")).to include(
          "revision_id" => revision.revision_id, "previous_rating" => 72
        )

        get revisions_path, headers: auth_headers_for(owner)
        expect(json.fetch("data").map { |take| take.fetch("revision_id") }).to eq([ revision.revision_id ])
      end

      it "is served to an Admin" do
        get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(create(:user, :admin))

        expect(json.dig("data", "draft_revision", "revision_id")).to eq(revision.revision_id)
      end

      {
        "another member" => -> { auth_headers_for(create(:user)) },
        "the service" => -> { service_headers }
      }.each do |who, headers|
        it "is hidden from #{who}" do
          get "/api/v1/reviews/#{review.review_id}", headers: instance_exec(&headers)
          expect(json.dig("data", "draft_revision")).to be_nil

          get revisions_path, headers: instance_exec(&headers)
          expect(json.fetch("data")).to eq([])
        end
      end
    end
  end

  describe "the current score" do
    def publish_revision(rating, at:)
      travel_to(at) do
        revision = create(:review_revision, :draft, review: review)
        patch "/api/v1/review_revisions/#{revision.revision_id}", params: { data: { rating: rating } },
          headers: auth_headers_for(owner), as: :json
        post "/api/v1/review_revisions/#{revision.revision_id}/publish", headers: auth_headers_for(owner), as: :json
        expect(response).to have_http_status(:ok)
        revision
      end
    end

    it "follows each publish, keeping the original and every take's score" do
      first = publish_revision(85, at: 3.days.ago)
      second = publish_revision(80, at: 1.day.ago)

      get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(create(:user))

      expect(json.fetch("data")).to include("rating" => 80, "original_rating" => 72)
      expect(json.dig("data", "revisions").map { |take| take.slice("revision_id", "rating", "previous_rating") })
        .to eq([
          { "revision_id" => first.revision_id, "rating" => 85, "previous_rating" => 72 },
          { "revision_id" => second.revision_id, "rating" => 80, "previous_rating" => 85 }
        ])
    end

    it "goes back to the previous score when a Revision is deleted" do
      publish_revision(85, at: 3.days.ago)
      second = publish_revision(80, at: 1.day.ago)

      delete "/api/v1/review_revisions/#{second.revision_id}", headers: auth_headers_for(owner)
      expect(response).to have_http_status(:ok)

      get "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)
      expect(json.fetch("data")).to include("rating" => 85, "original_rating" => 72)
    end

    it "is served in the member's and the game's review lists and the profile preview" do
      publish_revision(85, at: 1.day.ago)
      viewer = auth_headers_for(create(:user))

      get "/api/v1/users/#{owner.user_id}/reviews", headers: viewer
      expect(json.dig("data", 0)).to include("rating" => 85, "original_rating" => 72)

      get "/api/v1/games/#{review.gamedb_game_id}/reviews", headers: viewer
      expect(json.dig("data", 0)).to include("rating" => 85, "original_rating" => 72)

      get "/api/v1/users/#{owner.user_id}", headers: viewer
      expect(json.dig("data", "reviews", 0)).to include("rating" => 85, "original_rating" => 72)
    end

    describe "editing the first take of a revisited Review" do
      before { publish_revision(85, at: 1.day.ago) }

      def edit_review(data)
        patch "/api/v1/reviews/#{review.review_id}", params: { data: data }, headers: auth_headers_for(owner), as: :json
      end

      it "writes the first take's score from original_rating" do
        edit_review(original_rating: 75)

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("rating" => 85, "original_rating" => 75)
      end

      it "ignores a sent rating equal to the current score, as an editor resends it" do
        edit_review(rating: 85, title: "Retitled")

        expect(response).to have_http_status(:ok)
        expect(json.fetch("data")).to include("rating" => 85, "original_rating" => 72, "title" => "Retitled")
      end

      it "prefers original_rating over a sent rating" do
        edit_review(rating: 85, original_rating: 70)

        expect(json.fetch("data")).to include("rating" => 85, "original_rating" => 70)
      end
    end

    it "previews the profile's reviews newest published first" do
      older = travel_to(5.days.ago) { create(:review, :draft, user: owner) }
      travel_to(3.days.ago) { review }
      travel_to(1.day.ago) { older.publish! }

      get "/api/v1/users/#{owner.user_id}", headers: auth_headers_for(owner)

      expect(json.dig("data", "reviews").map { |r| r.fetch("review_id") }).to eq([ older.review_id, review.review_id ])
    end

    it "is deleted with its Review, Revisions and all" do
      revision = publish_revision(85, at: 1.day.ago)

      delete "/api/v1/reviews/#{review.review_id}", headers: auth_headers_for(owner)

      expect(response).to have_http_status(:ok)
      expect(UserGameReviewRevision.exists?(revision.revision_id)).to be(false)
    end
  end

  describe "Edit rules, counted from each Revision's own publish date" do
    let(:review) { travel_to(30.days.ago) { create(:review, user: owner, rating: 72) } }

    def edit(revision, data)
      patch "/api/v1/review_revisions/#{revision.revision_id}", params: { data: data },
        headers: auth_headers_for(owner), as: :json
    end

    it "lets a fresh Revision's score change though its Review is long locked" do
      revision = create(:review_revision, review: review, published_at: 2.days.ago)

      edit(revision, { rating: 90 })

      expect(response).to have_http_status(:ok)
      expect(json.fetch("data")).to include("rating" => 90)
    end

    it "locks a Revision's score 7 days after it was published, but not its text" do
      revision = create(:review_revision, review: review, published_at: 8.days.ago)

      edit(revision, { rating: 90 })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("error" => "score_locked")

      edit(revision, { title: "Typo fixed" })
      expect(response).to have_http_status(:ok)
    end

    it "marks an Edit more than an hour after publishing, not one within it" do
      fresh = create(:review_revision, review: review, published_at: 30.minutes.ago)
      edit(fresh, { title: "Quick fix" })
      expect(json.dig("data", "edited_at")).to be_nil

      fresh.update_columns(published_at: 2.hours.ago)
      edit(fresh, { title: "Later fix" })
      expect(json.dig("data", "edited_at")).to be_present
    end
  end

  describe "in the Review Feed" do
    let(:review) { travel_to(3.days.ago) { create(:review, user: owner, rating: 72, body: { "text" => "fine" }) } }

    def feed(params = {})
      get "/api/v1/reviews", params: params, headers: auth_headers_for(create(:user))
      json.fetch("data")
    end

    it "joins as its own entry, newest published first, with the score it replaced" do
      revision = create(:review_revision, review: review, rating: 85, title: "Replayed",
        body: { "text" => "better" }, published_at: 1.day.ago)

      entries = feed

      expect(entries.map { |entry| entry.values_at("kind", "review_id", "revision_id") })
        .to eq([ [ "revision", review.review_id, revision.revision_id ], [ "review", review.review_id, nil ] ])
      expect(entries.first).to include(
        "rating" => 85, "previous_rating" => 72, "title" => "Replayed", "body" => { "text" => "better" },
        "written" => true, "user_id" => owner.user_id, "gamedb_game_id" => review.gamedb_game_id
      )
      expect(entries.first.fetch("user")).to include("user_id" => owner.user_id)
      expect(entries.first.fetch("game")).to include("game_id" => review.gamedb_game_id)
      expect(entries.last).to include("rating" => 72, "previous_rating" => nil)
      expect(json.fetch("meta")).to include("count" => 2)
    end

    it "chains each Revision's previous score from the one before it" do
      create(:review_revision, review: review, rating: 85, published_at: 2.days.ago)
      create(:review_revision, review: review, rating: 80, published_at: 1.day.ago)

      expect(feed.map { |entry| entry.values_at("rating", "previous_rating") })
        .to eq([ [ 80, 85 ], [ 85, 72 ], [ 72, nil ] ])
    end

    it "leaves out Draft Revisions" do
      create(:review_revision, :draft, review: review)

      expect(feed.map { |entry| entry.fetch("kind") }).to eq(%w[review])
    end

    it "drops a score-only Revision with Written only" do
      create(:review_revision, review: review, body: nil, published_at: 1.day.ago)

      expect(feed(written: 1).map { |entry| entry.fetch("kind") }).to eq(%w[review])
      expect(json.fetch("meta")).to include("count" => 1)
    end
  end

  describe "in the author's drafts listing" do
    it "lists a Draft Revision beside Draft Reviews, newest last-touched first, with the score it replaces" do
      revision = travel_to(1.hour.ago) { create(:review_revision, :draft, review: review, title: "Again") }
      draft = travel_to(2.hours.ago) { create(:review, :draft, user: owner) }
      create(:review_revision, review: create(:review, user: owner))

      get "/api/v1/users/#{owner.user_id}/reviews/drafts", headers: auth_headers_for(owner)

      expect(json.fetch("data").map { |entry| entry.values_at("kind", "review_id", "revision_id") })
        .to eq([ [ "revision", review.review_id, revision.revision_id ], [ "review", draft.review_id, nil ] ])
      expect(json.dig("data", 0)).to include(
        "title" => "Again", "rating" => nil, "previous_rating" => 72, "published_at" => nil,
        "gamedb_game_id" => review.gamedb_game_id
      )
      expect(json.dig("data", 0, "game")).to include("game_id" => review.gamedb_game_id)
      expect(json.dig("data", 1)).to include("previous_rating" => nil)
      expect(json.fetch("meta")).to include("count" => 2)
    end
  end
end
