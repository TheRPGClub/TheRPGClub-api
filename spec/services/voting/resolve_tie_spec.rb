# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::ResolveTie do
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let(:tied_games) { create_list(:game, 3) }
  let(:tied_ids) { tied_games.map(&:game_id).sort }
  let(:round) do
    create(:voting_round, voting_opens_at: opens_at, closed_at: Time.utc(2026, 11, 2, 5),
      pending_ties: { "gotm" => tied_ids, "nr_gotm" => tied_ids.first(2) })
  end

  def resolve(category, ids)
    described_class.new(round, category: category, gamedb_game_ids: ids).call
  end

  it "records the pick and keeps the round tied while another category is pending" do
    resolve("gotm", [ tied_ids.last ])

    expect(GotmEntry.where(round_number: round.round_number).pluck(:gamedb_game_id)).to eq([ tied_ids.last ])
    expect(round.reload.pending_ties).to eq("nr_gotm" => tied_ids.first(2))
    expect(round.decided_at).to be_nil
  end

  it "decides the round once the last tie is broken, allowing several winners" do
    resolve("gotm", [ tied_ids.first ])
    resolve("nr_gotm", tied_ids.first(2))

    expect(NrGotmEntry.where(round_number: round.round_number).order(:game_index).pluck(:gamedb_game_id))
      .to eq(tied_ids.first(2))
    expect(round.reload.decided_at).to be_present
    expect(VotingRound.exists?(round.round_number + 1)).to be(true)
  end

  it "queues the round_decided post when automation is on" do
    allow(Voting).to receive(:automation_enabled?).and_return(true)
    resolve("gotm", [ tied_ids.first ])
    resolve("nr_gotm", [ tied_ids.first ])

    event = VotingEvent.find_by!(round_number: round.round_number, kind: "round_decided")
    expect(event.payload).to eq("winners" => { "gotm" => [ tied_ids.first ], "nr_gotm" => [ tied_ids.first ] })
  end

  it "settles a category while its runoff is still open" do
    closes = Time.utc(2026, 11, 3, 5)
    round.update!(runoff_ties: round.pending_ties, runoff_opens_at: round.closed_at, runoff_closes_at: closes)

    resolve("gotm", [ tied_ids.first ])

    expect(round.reload.pending_ties).to eq("nr_gotm" => tied_ids.first(2))
    expect(round.phase(closes - 1.hour)).to eq("runoff")

    resolve("nr_gotm", [ tied_ids.first ])

    expect(round.reload.phase(closes - 1.hour)).to eq("decided")
  end

  it "rejects a game that is not part of the tie" do
    expect { resolve("gotm", [ create(:game).game_id ]) }.to raise_error(described_class::InvalidPickError)
  end

  it "rejects an empty pick" do
    expect { resolve("gotm", []) }.to raise_error(described_class::InvalidPickError)
  end

  it "rejects a category with no tie" do
    round.update!(pending_ties: { "gotm" => tied_ids })

    expect { resolve("nr_gotm", [ tied_ids.first ]) }.to raise_error(described_class::NoTieError)
  end
end
