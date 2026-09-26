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
  subject(:service) { described_class.new(vote_model: GotmVote, nomination_model: GotmNomination) }

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

    it "places a vote and reports the small-field cap" do
      nomination = create_nomination!(101)

      result = cast!("voter", nomination)

      expect(result.action).to eq("voted")
      expect(result.vote.nomination_id).to eq(nomination.nomination_id)
      expect(result.vote.gamedb_game_id).to eq(101)
      expect(result.vote.voted_at).to be_present
      expect(result.removed_votes).to be_empty
      expect(result.cap).to eq(2)
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

    it "evicts the oldest vote when a new game is cast at the cap" do
      nominations = [ 101, 102, 103 ].map { |game_id| create_nomination!(game_id) }
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])

      result = cast!("voter", nominations[2])

      expect(result.action).to eq("voted")
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ 101 ])
      expect(result.warning).to include("vote cap (2)")
      expect(held_game_ids("voter")).to eq([ 102, 103 ])
    end

    it "keeps the small cap at 8 nominations" do
      nominations = (1..8).map { |i| create_nomination!(100 + i) }

      result = cast!("voter", nominations[0])

      expect(result.cap).to eq(2)
      expect(described_class.cap_for(GotmNomination, round)).to eq(2)
    end

    it "grants the large cap at 9 nominations" do
      nominations = (1..9).map { |i| create_nomination!(100 + i) }
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])

      result = cast!("voter", nominations[2])

      expect(result.cap).to eq(3)
      expect(result.removed_votes).to be_empty
      expect(held_game_ids("voter")).to eq([ 101, 102, 103 ])
    end

    it "evicts enough votes to recover when the cap shrank mid-round" do
      nominations = (1..9).map { |i| create_nomination!(100 + i) }
      cast!("voter", nominations[0])
      cast!("voter", nominations[1])
      cast!("voter", nominations[2])
      # An admin deleting a nomination drops the round to 8 and the cap to 2,
      # leaving the voter one over. The next cast must evict two to fit.
      nominations[8].destroy!

      result = cast!("voter", nominations[3])

      expect(result.cap).to eq(2)
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ 101, 102 ])
      expect(result.warning).to include("oldest votes")
      expect(held_game_ids("voter")).to eq([ 103, 104 ])
    end
  end

  describe "the Non-RPG twin" do
    it "casts through the NR models unchanged" do
      create_round!
      nomination = NrGotmNomination.create!(round_number: round, user_id: "nominator", gamedb_game_id: 101)
      nr_service = described_class.new(vote_model: NrGotmVote, nomination_model: NrGotmNomination)

      result = nr_service.cast!(round_number: round, user_id: "voter", nomination_id: nomination.nomination_id)

      expect(result.action).to eq("voted")
      expect(NrGotmVote.where(round_number: round, user_id: "voter").count).to eq(1)
    end
  end
end
