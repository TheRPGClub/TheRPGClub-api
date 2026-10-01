# frozen_string_literal: true

require 'rails_helper'

# Behavioral coverage for the vote-casting rules — the one genuinely stateful
# algorithm behind the votes endpoints (the request specs are rswag doc-only
# and never exercise it). Runs against the real test database with plain
# ActiveRecord setup, matching the repo's no-fixtures/no-factories stance.
# The GOTM pair is exercised throughout; NrGotmVote/NrGotmNomination share the
# identical shape and code path (the service is handed the model pair), so a
# single smoke test covers the twin.
RSpec.describe Voting::CastVote do
  subject(:service) { described_class.new(category: "gotm") }

  let(:round) { 999_001 }

  def create_round!(opens_at: 1.hour.ago, closes_at: 1.day.from_now, **attrs)
    VotingRound.create!(round_number: round, voting_opens_at: opens_at, voting_closes_at: closes_at, **attrs)
  end

  # Nominations are unique per (round, user), so each gets its own nominator.
  def create_nomination!(game_id, nominator: "nominator-#{game_id}")
    GotmNomination.create!(round_number: round, user_id: nominator, gamedb_game_id: game_id)
  end

  def cast!(user_id, nomination)
    service.cast!(round_number: round, user_id: user_id, nomination_id: nomination.nomination_id)
  end

  def held_game_ids(user_id)
    GotmVote.where(round_number: round, user_id: user_id)
      .order(voted_at: :asc, vote_id: :asc).pluck(:gamedb_game_id)
  end

  describe "the voting window" do
    let(:nomination) { create_nomination!(101) }

    it "rejects a cast when the round is not scheduled" do
      expect { cast!("voter", nomination) }
        .to raise_error(described_class::VotingClosedError, /not scheduled/)
    end

    it "rejects a cast before voting opens" do
      create_round!(opens_at: 1.hour.from_now, closes_at: 3.days.from_now)

      expect { cast!("voter", nomination) }
        .to raise_error(described_class::VotingClosedError, /not opened yet/)
    end

    it "rejects a cast after the close" do
      create_round!(opens_at: 3.days.ago, closes_at: 1.minute.ago)

      expect { cast!("voter", nomination) }
        .to raise_error(described_class::VotingClosedError, /closed at/)
    end

    it "rejects a cast once the round is decided, even inside the window" do
      create_round!(decided_at: 1.minute.ago)

      expect { cast!("voter", nomination) }
        .to raise_error(described_class::VotingClosedError, /closed at/)
    end
  end

  describe "casting" do
    before { create_round! }

    it "places a vote and reports the cap" do
      nomination = create_nomination!(101)

      result = cast!("voter", nomination)

      expect(result.action).to eq("voted")
      expect(result.vote.nomination_id).to eq(nomination.nomination_id)
      expect(result.vote.gamedb_game_id).to eq(101)
      expect(result.vote.voted_at).to be_present
      expect(result.removed_votes).to be_empty
      expect(result.cap).to eq(1)
      expect(result.warning).to be_nil
    end

    it "rejects a nomination from another round" do
      other = GotmNomination.create!(round_number: round + 1, user_id: "nominator-x", gamedb_game_id: 101)

      expect { cast!("voter", other) }
        .to raise_error(described_class::NominationNotFoundError)
    end

    it "rejects an unknown nomination" do
      expect { service.cast!(round_number: round, user_id: "voter", nomination_id: -1) }
        .to raise_error(described_class::NominationNotFoundError)
    end

    it "rejects a nomination without a game" do
      bare = GotmNomination.create!(round_number: round, user_id: "nominator-bare")

      expect { cast!("voter", bare) }
        .to raise_error(described_class::NominationMissingGameError)
    end
  end

  describe "toggling off" do
    before { create_round! }

    it "takes the vote back when the same nomination is cast twice" do
      nomination = create_nomination!(101)
      cast!("voter", nomination)

      result = cast!("voter", nomination)

      expect(result.action).to eq("unvoted")
      expect(result.vote).to be_nil
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ 101 ])
      expect(result.warning).to include("takes the vote back")
      expect(held_game_ids("voter")).to be_empty
    end

    it "takes the vote back via a different nomination of the same game" do
      first = create_nomination!(101, nominator: "nominator-a")
      second = create_nomination!(101, nominator: "nominator-b")
      cast!("voter", first)

      result = cast!("voter", second)

      expect(result.action).to eq("unvoted")
      expect(held_game_ids("voter")).to be_empty
    end
  end

  describe "the cap" do
    before { create_round! }

    def nominate_games!(count)
      (1..count).map { |i| create_nomination!(100 + i) }
    end

    it "is half the distinct games, rounded down, with a minimum of 1" do
      { 0 => 1, 1 => 1, 4 => 2, 7 => 3, 10 => 5, 15 => 7 }.each do |games, cap|
        GotmNomination.where(round_number: round).delete_all
        nominate_games!(games)

        expect(described_class.cap_for(GotmNomination, round)).to eq(cap), "#{games} games"
      end
    end

    it "counts a game nominated twice once" do
      nominate_games!(3)
      create_nomination!(101, nominator: "second-nominator")

      expect(described_class.cap_for(GotmNomination, round)).to eq(1)
    end

    it "does not count a nomination without a game" do
      nominate_games!(3)
      GotmNomination.create!(round_number: round, user_id: "nominator-bare")

      expect(described_class.cap_for(GotmNomination, round)).to eq(1)
    end

    it "evicts the oldest vote when a new game is cast at the cap" do
      nominations = nominate_games!(4)
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])

      result = cast!("voter", nominations[2])

      expect(result.action).to eq("voted")
      expect(result.cap).to eq(2)
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ 101 ])
      expect(result.warning).to include("vote cap (2)")
      expect(held_game_ids("voter")).to eq([ 102, 103 ])
    end

    it "lets a larger field hold more votes" do
      nominations = nominate_games!(7)
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])

      result = cast!("voter", nominations[2])

      expect(result.cap).to eq(3)
      expect(result.removed_votes).to be_empty
      expect(held_game_ids("voter")).to eq([ 101, 102, 103 ])
    end

    it "evicts enough votes to recover when the cap shrank mid-round" do
      nominations = nominate_games!(6)
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])
      cast!("voter", nominations[2])
      # An admin deleting two nominations drops the round to 4 games and the
      # cap to 2, leaving the voter one over. The next cast must evict two.
      nominations[4].destroy!
      nominations[5].destroy!

      result = cast!("voter", nominations[3])

      expect(result.cap).to eq(2)
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ 101, 102 ])
      expect(result.warning).to include("oldest votes")
      expect(held_game_ids("voter")).to eq([ 103, 104 ])
    end
  end

  describe "the runoff" do
    let(:tied) { [ create_nomination!(101), create_nomination!(102) ] }
    let(:untied) { create_nomination!(103) }

    def open_runoff!(closes_at: 1.hour.from_now)
      ties = { "gotm" => [ 101, 102 ] }
      create_round!(opens_at: 3.days.ago, closes_at: 2.hours.ago, closed_at: 2.hours.ago,
        pending_ties: ties, runoff_ties: ties, runoff_opens_at: 2.hours.ago, runoff_closes_at: closes_at)
    end

    it "casts a separate runoff vote with a cap of 1, leaving the main votes alone" do
      open_runoff!
      GotmVote.create!(round_number: round, user_id: "voter", nomination_id: tied[0].nomination_id,
        gamedb_game_id: 101)

      first = cast!("voter", tied[0])
      second = cast!("voter", tied[1])

      expect(first).to have_attributes(action: "voted", runoff: true, cap: 1)
      expect(second.removed_votes.map(&:gamedb_game_id)).to eq([ 101 ])
      expect(GotmVote.where(round_number: round, user_id: "voter").pluck(:runoff, :gamedb_game_id))
        .to contain_exactly([ false, 101 ], [ true, 102 ])
    end

    it "refuses a game that did not tie" do
      open_runoff!

      expect { cast!("voter", untied) }.to raise_error(described_class::GameNotInRunoffError)
    end

    it "refuses a category with no runoff" do
      open_runoff!
      nomination = NrGotmNomination.create!(round_number: round, user_id: "nominator", gamedb_game_id: 101)

      expect {
        described_class.new(category: "nr_gotm")
          .cast!(round_number: round, user_id: "voter", nomination_id: nomination.nomination_id)
      }.to raise_error(described_class::VotingClosedError, /no nr_gotm runoff/)
    end

    it "refuses a cast once the runoff has closed" do
      open_runoff!(closes_at: 1.minute.ago)

      expect { cast!("voter", tied[0]) }.to raise_error(described_class::VotingClosedError, /runoff .* closed at/)
    end
  end

  describe "the Non-RPG twin" do
    it "casts through the NR models unchanged" do
      create_round!
      nomination = NrGotmNomination.create!(round_number: round, user_id: "nominator", gamedb_game_id: 101)
      nr_service = described_class.new(category: "nr_gotm")

      result = nr_service.cast!(round_number: round, user_id: "voter", nomination_id: nomination.nomination_id)

      expect(result.action).to eq("voted")
      expect(NrGotmVote.where(round_number: round, user_id: "voter").count).to eq(1)
    end
  end
end
