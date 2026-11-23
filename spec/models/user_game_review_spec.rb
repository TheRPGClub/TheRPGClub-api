# frozen_string_literal: true

require "rails_helper"

# A Review is a Draft until its author publishes it (spec api#430). A Draft
# may have no score yet; a Published Review always has one, enforced by the
# model and, under it, by a check constraint.
RSpec.describe UserGameReview do
  include ActiveSupport::Testing::TimeHelpers

  describe "a Draft" do
    it "may have no score" do
      review = create(:review, :draft, rating: nil)

      expect(review).to be_persisted
      expect(review).to be_draft
    end
  end

  describe "a Published Review" do
    it "needs a score" do
      review = build(:review, rating: nil)

      expect(review).not_to be_valid
      expect(review.errors.details[:rating]).to include(error: :rating_required)
    end

    it "can't lose its score even past the model (check constraint)" do
      review = create(:review)

      expect { review.update_column(:rating, nil) }.to raise_error(ActiveRecord::StatementInvalid, /rating_when_published/)
    end
  end

  describe "#publish!" do
    it "dates a Draft with a score as Published" do
      review = create(:review, :draft, rating: 70)

      freeze_time do
        review.publish!

        expect(review.reload.published_at).to eq(Time.current)
      end
      expect(review).to be_published
    end

    it "refuses a Draft without a score" do
      review = create(:review, :draft, rating: nil)

      expect { review.publish! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(review.reload).to be_draft
    end

    it "keeps the first publish date when published again" do
      first = 3.days.ago.change(usec: 0)
      review = create(:review, published_at: first)

      review.publish!

      expect(review.reload.published_at).to eq(first)
    end
  end

  describe ".published" do
    it "covers Published Reviews only" do
      published = create(:review)
      create(:review, :draft)

      expect(described_class.published).to contain_exactly(published)
    end
  end
end
