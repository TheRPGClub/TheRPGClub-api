# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::Backfill do
  include ActiveSupport::Testing::TimeHelpers

  let(:last_decided) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }
  let(:opens_at) { Time.utc(2026, 9, 25, 16) }

  before { create(:gotm_entry, round_number: last_decided) }

  # Production on 2026-09-26: round 142 has winners, the wizard re-dated its
  # row to this month's vote, and nobody has run /admin voting-open, so no row
  # exists for 143. The site showed 142's finished ballot as open.
  it "creates the round after the last decided one from the decided round's re-dated row" do
    BotVotingInfo.create!(round_number: last_decided - 1, next_vote_at: opens_at - 30.days)
    BotVotingInfo.create!(round_number: last_decided, next_vote_at: opens_at, vote_ends_at: opens_at - 28.days)

    described_class.call

    round = VotingRound.sole
    expect(round.round_number).to eq(last_decided + 1)
    expect(round.voting_opens_at).to eq(opens_at)
    # The decided row's vote_ends_at belongs to its own, earlier vote.
    expect(round.voting_closes_at).to be_within(1.second).of(Voting::Schedule.default_closes_at(opens_at))
    travel_to(Time.utc(2026, 9, 26, 12)) { expect(VotingRound.current.phase).to eq("voting") }
  end

  it "prefers the round's own row when /admin voting-open already created it" do
    BotVotingInfo.create!(round_number: last_decided, next_vote_at: opens_at)
    close = opens_at + 2.days
    BotVotingInfo.create!(round_number: last_decided + 1, next_vote_at: opens_at + 1.hour, vote_ends_at: close)

    described_class.call

    expect(VotingRound.sole).to have_attributes(voting_opens_at: opens_at + 1.hour, voting_closes_at: close)
  end

  it "does nothing once voting_rounds has rows" do
    create(:voting_round)
    BotVotingInfo.create!(round_number: last_decided, next_vote_at: opens_at)

    expect { described_class.call }.not_to change(VotingRound, :count)
  end

  it "does nothing without a scheduled vote" do
    expect { described_class.call }.not_to change(VotingRound, :count)
  end
end
