# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::DecideRound do
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let(:after_close) { Time.utc(2026, 11, 3, 12) }
  let(:round) { create(:voting_round, voting_opens_at: opens_at) }

  def nominate(model, **attrs)
    create(model, round_number: round.round_number, **attrs)
  end

  def vote_for(factory, nomination, count)
    create_list(factory, count, nomination: nomination)
  end

  it "records each category's sole leader, decides the round and schedules the next" do
    gotm_winner = nominate(:gotm_nomination)
    vote_for(:gotm_vote, gotm_winner, 3)
    vote_for(:gotm_vote, nominate(:gotm_nomination), 1)
    nr_winner = nominate(:nr_gotm_nomination)
    vote_for(:nr_gotm_vote, nr_winner, 2)

    result = described_class.new(round, now: after_close).call

    expect(result.winners).to eq(
      "gotm" => [ gotm_winner.gamedb_game_id ], "nr_gotm" => [ nr_winner.gamedb_game_id ]
    )
    expect(result.ties).to eq({})
    expect(GotmEntry.where(round_number: round.round_number).sole)
      .to have_attributes(gamedb_game_id: gotm_winner.gamedb_game_id, game_index: 0, month_year: "November 2026")
    expect(round.reload.phase(after_close)).to eq("decided")
    expect(VotingRound.current.round_number).to eq(round.round_number + 1)
  end

  it "counts a game's votes across its nominations" do
    game = create(:game)
    first = nominate(:gotm_nomination, game: game)
    second = nominate(:gotm_nomination, game: game)
    rival = nominate(:gotm_nomination)
    vote_for(:gotm_vote, first, 1)
    vote_for(:gotm_vote, second, 1)
    vote_for(:gotm_vote, rival, 1)

    result = described_class.new(round, now: after_close).call

    expect(result.winners.fetch("gotm")).to eq([ game.game_id ])
  end

  it "leaves a shared lead pending and the round undecided" do
    tied = [ nominate(:gotm_nomination), nominate(:gotm_nomination) ]
    tied.each { |nomination| vote_for(:gotm_vote, nomination, 2) }

    result = described_class.new(round, now: after_close).call

    expect(result.ties).to eq("gotm" => tied.map(&:gamedb_game_id).sort)
    expect(GotmEntry.where(round_number: round.round_number)).to be_empty
    expect(round.reload.phase(after_close)).to eq("tie")
    expect(VotingRound.exists?(round.round_number + 1)).to be(false)
  end

  it "records no winner for a category nobody voted in" do
    nominate(:gotm_nomination)
    nominate(:nr_gotm_nomination)

    result = described_class.new(round, now: after_close).call

    expect(result.winners).to eq({})
    expect(round.reload.decided_at).to eq(after_close)
  end

  it "keeps a winner an admin already recorded instead of duplicating it" do
    winner = nominate(:gotm_nomination)
    vote_for(:gotm_vote, winner, 1)
    create(:gotm_entry, round_number: round.round_number, game: winner.game, game_index: 0)

    described_class.new(round, now: after_close).call

    expect(GotmEntry.where(round_number: round.round_number).count).to eq(1)
  end

  it "is a no-op once the round has been closed" do
    vote_for(:gotm_vote, nominate(:gotm_nomination), 1)
    described_class.new(round, now: after_close).call

    expect { described_class.new(round, now: after_close + 1.hour).call }
      .not_to change { GotmEntry.where(round_number: round.round_number).count }
  end

  it "refuses to decide while voting is still open" do
    expect { described_class.new(round, now: opens_at + 1.hour).call }
      .to raise_error(described_class::VotingNotClosedError)
  end
end
