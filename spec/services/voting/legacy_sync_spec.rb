# frozen_string_literal: true

require "rails_helper"

# The bot's bookkeeping mirrored into voting_rounds while it still drives the
# lifecycle. Row semantics: bot_voting_info[R].next_vote_at is round R's vote
# while R is undecided, and round R + 1's once R has GOTM winners.
RSpec.describe Voting::LegacySync do
  let(:decided) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }

  before { create(:gotm_entry, round_number: decided) }

  def write_info(round_number, **attrs)
    info = BotVotingInfo.find_or_initialize_by(round_number: round_number)
    info.update!({ next_vote_at: opens_at }.merge(attrs))
    described_class.voting_info_written(info)
  end

  it "reads a decided round's re-dated row as the next round's vote (wizard, set-nextvote)" do
    write_info(decided)

    expect(VotingRound.find(decided + 1)).to have_attributes(voting_opens_at: opens_at, decided_at: nil)
  end

  it "reads an undecided round's own row as its vote, override included (voting-open, voting-close)" do
    write_info(decided + 1)
    expect(VotingRound.find(decided + 1).voting_opens_at).to eq(opens_at)

    close = opens_at + 1.hour
    write_info(decided + 1, vote_ends_at: close)
    expect(VotingRound.find(decided + 1).voting_closes_at).to eq(close)
  end

  it "never reschedules a decided round" do
    create(:voting_round, round_number: decided + 1, voting_opens_at: opens_at, decided_at: opens_at + 3.days)

    write_info(decided + 1, next_vote_at: opens_at + 30.days)

    expect(VotingRound.find(decided + 1).voting_opens_at).to eq(opens_at)
  end

  it "decides a round when its winners are recorded, scheduling the next one" do
    round = create(:voting_round, round_number: decided + 1, voting_opens_at: opens_at)

    described_class.winner_recorded(round.round_number)

    expect(round.reload.decided_at).to be_present
    expect(VotingRound.find(decided + 2)).to be_present
  end

  it "ignores winners recorded for a round it does not track" do
    expect { described_class.winner_recorded(decided - 50) }.not_to change(VotingRound, :count)
  end

  it "stands down once the backend runs the lifecycle itself" do
    allow(Voting).to receive(:automation_enabled?).and_return(true)

    write_info(decided)

    expect(VotingRound.exists?(decided + 1)).to be(false)
  end
end
