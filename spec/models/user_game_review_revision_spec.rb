# frozen_string_literal: true

require "rails_helper"

# A Revision is a dated return to a Published Review (spec api#430). Like a
# Review, a Draft Revision may have no score but a Published one always has
# one, and its scorecard is validated like a Review's.
RSpec.describe UserGameReviewRevision do
  describe "a Published Revision" do
    it "needs a score" do
      revision = build(:review_revision, rating: nil)

      expect(revision).not_to be_valid
      expect(revision.errors.details[:rating]).to include(error: :rating_required)
    end

    it "can't lose its score even past the model (check constraint)" do
      revision = create(:review_revision)

      expect { revision.update_column(:rating, nil) }
        .to raise_error(ActiveRecord::StatementInvalid, /rating_when_published/)
    end
  end

  describe "its scorecard" do
    it "accepts a card a Review would accept" do
      revision = build(:review_revision,
        facets: { "template" => "custom", "order" => %w[story custom:1], "labels" => { "custom:1" => "Jobs" },
                  "scores" => { "story" => 90 }, "weights" => { "story" => 60, "custom:1" => 40 } })

      expect(revision).to be_valid
    end

    it "refuses a card a Review would refuse" do
      revision = build(:review_revision,
        facets: { "template" => "rpg", "order" => %w[story], "scores" => { "story" => 101 } })

      expect(revision).not_to be_valid
      expect(revision.errors[:facets].join).to include("scores must be integers in 0..100")
    end

    it "stores an empty card as no card, like a Review" do
      revision = create(:review_revision, facets: { "template" => "rpg", "order" => [] })

      expect(revision.reload.facets).to be_nil
    end
  end

  it "keeps a second Draft Revision out even past the model (unique index)" do
    review = create(:review)
    create(:review_revision, :draft, review: review)

    expect { described_class.new(review: review).save(validate: false) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end
end
