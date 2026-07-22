# frozen_string_literal: true

require 'rails_helper'

# Behavioral coverage for the nomination-window rule behind the member
# nomination writes (the nominations request specs are rswag doc-only). Plain
# ActiveRecord setup, matching the repo's no-fixtures/no-factories stance.
RSpec.describe BotVotingInfo do
  describe ".nominations_open_for?" do
    let(:current_round) { 999_101 }

    def create_current_round!(next_vote_at: 2.days.from_now)
      BotVotingInfo.create!(round_number: current_round, next_vote_at: next_vote_at)
    end

    it "is false when no rounds exist" do
      expect(BotVotingInfo.nominations_open_for?(1)).to be(false)
    end

    it "is open only for the round after the current one, before its vote opens" do
      create_current_round!

      expect(BotVotingInfo.nominations_open_for?(current_round + 1)).to be(true)
    end

    it "accepts the round as a string (path params arrive as strings)" do
      create_current_round!

      expect(BotVotingInfo.nominations_open_for?((current_round + 1).to_s)).to be(true)
    end

    it "is closed for the current round itself (its field is frozen)" do
      create_current_round!

      expect(BotVotingInfo.nominations_open_for?(current_round)).to be(false)
    end

    it "is closed for rounds beyond the next one" do
      create_current_round!

      expect(BotVotingInfo.nominations_open_for?(current_round + 2)).to be(false)
    end

    it "closes when the current round's vote opens" do
      create_current_round!(next_vote_at: 1.minute.ago)

      expect(BotVotingInfo.nominations_open_for?(current_round + 1)).to be(false)
    end

    it "keys off the highest round, not any matching predecessor" do
      create_current_round!
      BotVotingInfo.create!(round_number: current_round + 1, next_vote_at: 30.days.from_now)

      # Round current+1 now exists as the highest row, so nominations have
      # moved on to current+2; the round that was open is frozen.
      expect(BotVotingInfo.nominations_open_for?(current_round + 1)).to be(false)
      expect(BotVotingInfo.nominations_open_for?(current_round + 2)).to be(true)
    end
  end
end
