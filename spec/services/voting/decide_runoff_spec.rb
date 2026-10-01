# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::DecideRunoff do
  let(:closed_at) { Time.utc(2026, 11, 2, 5) }
  let(:runoff_closes_at) { closed_at + 1.day }
  let(:after_runoff) { runoff_closes_at + 1.minute }
  let(:games) { create_list(:game, 3) }
  let(:ids) { games.map(&:game_id).sort }
  let(:round) do
    ties = { "gotm" => ids.first(2), "nr_gotm" => ids }
    create(:voting_round, voting_opens_at: Time.utc(2026, 10, 30, 16), closed_at: closed_at,
      pending_ties: ties, runoff_ties: ties, runoff_opens_at: closed_at, runoff_closes_at: runoff_closes_at)
  end

  # One nomination per game and category, reused across its votes.
  def nomination(category, game_id)
    Voting.models_for(category).fetch(:nomination).find_by(round_number: round.round_number, gamedb_game_id: game_id) ||
      create(:"#{category}_nomination", round_number: round.round_number, game: GamedbGame.find(game_id))
  end

  def runoff_votes(category, game_id, count)
    create_list(:"#{category}_vote", count, nomination: nomination(category, game_id), runoff: true)
  end

  def main_votes(category, game_id, count)
    create_list(:"#{category}_vote", count, nomination: nomination(category, game_id))
  end

  def decide(now = after_runoff)
    described_class.new(round, now: now).call
  end

  it "records each category's runoff leader and decides the round" do
    main_votes("gotm", ids[0], 3)
    runoff_votes("gotm", ids[1], 2)
    runoff_votes("gotm", ids[0], 1)
    runoff_votes("nr_gotm", ids[2], 1)

    result = decide

    expect(result.winners).to eq("gotm" => [ ids[1] ], "nr_gotm" => [ ids[2] ])
    expect(result.ties).to eq({})
    expect(round.reload).to have_attributes(runoff_closed_at: after_runoff, decided_at: after_runoff)
    expect(VotingRound.current.round_number).to eq(round.round_number + 1)
  end

  it "leaves a runoff that tied again for an admin, narrowed to its leaders" do
    runoff_votes("gotm", ids[1], 1)
    runoff_votes("nr_gotm", ids[0], 1)
    runoff_votes("nr_gotm", ids[1], 1)

    result = decide

    expect(result.winners).to eq("gotm" => [ ids[1] ])
    expect(result.ties).to eq("nr_gotm" => ids.first(2))
    expect(round.reload).to have_attributes(decided_at: nil, runoff_closed_at: after_runoff)
    expect(round.phase(after_runoff)).to eq("tie")
  end

  it "leaves the whole tie for an admin when nobody voted in the runoff" do
    runoff_votes("gotm", ids[0], 1)

    result = decide

    expect(result.ties).to eq("nr_gotm" => ids)
  end

  it "does not revisit a category an admin settled during the runoff" do
    Voting::ResolveTie.new(round, category: "gotm", gamedb_game_ids: [ ids[0] ], now: closed_at + 1.hour).call
    runoff_votes("gotm", ids[1], 3)
    runoff_votes("nr_gotm", ids[2], 1)

    result = decide

    expect(GotmEntry.where(round_number: round.round_number).pluck(:gamedb_game_id)).to eq([ ids[0] ])
    expect(result.winners).to eq("gotm" => [ ids[0] ], "nr_gotm" => [ ids[2] ])
  end

  it "is a no-op once the runoff has been tallied" do
    runoff_votes("gotm", ids[0], 1)
    decide

    expect { decide(after_runoff + 1.hour) }.not_to change { round.reload.runoff_closed_at }
  end

  it "refuses to decide while the runoff is open" do
    expect { decide(runoff_closes_at - 1.minute) }.to raise_error(described_class::RunoffNotClosedError)
  end
end
