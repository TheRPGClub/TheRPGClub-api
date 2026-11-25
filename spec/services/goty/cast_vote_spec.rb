# frozen_string_literal: true

require "rails_helper"

# Voting on a GOTY Vote's Awards (spec api#471, ticket api#474). The rules
# are the GOTM round's (Voting::CastRules, covered by
# spec/services/voting/cast_vote_spec.rb); these cover what is per Award.
RSpec.describe Goty::CastVote do
  include ActiveSupport::Testing::TimeHelpers

  let!(:vote) { create(:goty_vote, year: 2026, candidates_frozen_at: Time.utc(2027, 1, 15, 17)) }
  let(:voting) { vote.voting_opens_at + 1.hour }
  let(:voter) { create(:user) }

  def candidates!(award, count)
    create_list(:game, count).each_with_index.map do |game, position|
      GotyCandidate.create!(year: 2026, award: award, gamedb_game_id: game.game_id, position: position)
      game.game_id
    end
  end

  def cast(award, game_id, user: voter, at: voting)
    travel_to(at) do
      described_class.call(year: 2026, award: award, user_id: user.user_id, gamedb_game_id: game_id)
    end
  end

  def held(award, runoff: false)
    GotyBallotVote.where(year: 2026, award: award, user_id: voter.user_id, runoff: runoff)
      .order(:voted_at, :id).pluck(:gamedb_game_id)
  end

  describe "the voting window" do
    let(:games) { candidates!("gotm", 3) }

    it "is closed before voting opens" do
      expect { cast("gotm", games.first, at: vote.voting_opens_at - 1.minute) }
        .to raise_error(Voting::CastRules::VotingClosedError, /GOTY Vote 2026 has not opened yet/)
    end

    it "is closed once voting has closed" do
      expect { cast("gotm", games.first, at: vote.voting_closes_at + 1.minute) }
        .to raise_error(Voting::CastRules::VotingClosedError, /closed at/)
    end

    # A cast checked just before the close must not land after the close
    # tallied: the window is checked again under the GOTY Vote's row lock.
    it "refuses a cast whose window closed while it was being checked" do
      games
      allow(Voting::CastRules).to receive(:lock!).and_wrap_original do |original, *args|
        original.call(*args)
        GotyVote.where(year: 2026).update_all(closed_at: vote.voting_closes_at)
      end

      expect { cast("gotm", games.first, at: vote.voting_closes_at - 1.second) }
        .to raise_error(Voting::CastRules::VotingClosedError, /closed at/)
      expect(GotyBallotVote.count).to eq(0)
    end

    it "is closed once the vote was tallied, even if the close was moved later" do
      vote.update!(closed_at: vote.voting_closes_at, voting_closes_at: vote.voting_closes_at + 1.day)

      expect { cast("gotm", games.first, at: vote.voting_closes_at - 1.hour) }
        .to raise_error(Voting::CastRules::VotingClosedError, /closed at/)
    end
  end

  describe "casting on an Award" do
    it "votes, with a cap of half the Award's candidates" do
      games = candidates!("gotm", 5)

      result = cast("gotm", games.first)

      expect(result).to have_attributes(action: "voted", cap: 2, runoff: false, removed_votes: [])
      expect(result.vote).to have_attributes(year: 2026, award: "gotm", gamedb_game_id: games.first)
      expect(result.vote.voted_at).to be_present
    end

    it "toggles a vote off when the game is voted again" do
      games = candidates!("gotm", 4)
      cast("gotm", games.first)

      result = cast("gotm", games.first)

      expect(result.action).to eq("unvoted")
      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ games.first ])
      expect(held("gotm")).to eq([])
    end

    it "evicts the oldest vote at the cap and says so" do
      games = candidates!("gotm", 4)
      cast("gotm", games[0])
      cast("gotm", games[1], at: voting + 1.minute)

      result = cast("gotm", games[2], at: voting + 2.minutes)

      expect(result.removed_votes.map(&:gamedb_game_id)).to eq([ games[0] ])
      expect(result.warning).to match(/vote cap \(2\)/)
      expect(held("gotm")).to eq([ games[1], games[2] ])
    end

    it "keeps each Award's votes and cap apart, and lets a game stand in several Awards" do
      shared = create(:game)
      gotm = candidates!("gotm", 3)
      candidates!("game_of_the_year", 5)
      [ "gotm", "game_of_the_year" ].each do |award|
        GotyCandidate.create!(year: 2026, award: award, gamedb_game_id: shared.game_id, position: 9)
      end

      cast("gotm", shared.game_id)
      cast("gotm", gotm.first, at: voting + 1.minute)
      result = cast("game_of_the_year", shared.game_id, at: voting + 2.minutes)

      expect(result).to have_attributes(action: "voted", cap: 3, removed_votes: [])
      expect(held("gotm")).to eq([ shared.game_id, gotm.first ])
      expect(held("game_of_the_year")).to eq([ shared.game_id ])
    end

    it "refuses a game that is not one of the Award's candidates" do
      candidates!("gotm", 3)
      other = candidates!("nr_gotm", 3).first

      expect { cast("gotm", other) }.to raise_error(described_class::NotACandidateError)
    end

    it "refuses votes on an uncontested Award" do
      only = candidates!("nr_gotm", 1).first

      expect { cast("nr_gotm", only) }.to raise_error(described_class::UncontestedError)
    end

    it "refuses an unknown Award" do
      expect { cast("best_boss", 1) }.to raise_error(described_class::UnknownAwardError)
    end

    it "freezes the candidates first when the sweep has not yet" do
      vote.update!(candidates_frozen_at: nil)
      games = create_list(:game, 2)
      games.each_with_index do |game, index|
        create(:gotm_entry, round_number: 900_000 + index, month_year: "#{%w[May June][index]} 2026", game: game)
      end

      result = cast("gotm", games.last.game_id)

      expect(result.action).to eq("voted")
      expect(GotyCandidate.ballot(2026, "gotm").pluck(:gamedb_game_id)).to eq(games.map(&:game_id))
    end
  end

  describe "the runoff" do
    let(:games) { candidates!("game_of_the_year", 4) }
    let(:runoff_at) { vote.voting_closes_at + 1.hour }

    before do
      ties = { "game_of_the_year" => games.first(2) }
      vote.update!(closed_at: vote.voting_closes_at, pending_ties: ties, runoff_ties: ties,
        runoff_opens_at: vote.voting_closes_at, runoff_closes_at: vote.voting_closes_at + 1.day)
    end

    it "takes one vote, for a tied game, apart from the main vote" do
      first = cast("game_of_the_year", games[0], at: runoff_at)
      second = cast("game_of_the_year", games[1], at: runoff_at + 1.minute)

      expect(first).to have_attributes(action: "voted", cap: 1, runoff: true)
      expect(second.removed_votes.map(&:gamedb_game_id)).to eq([ games[0] ])
      expect(held("game_of_the_year", runoff: true)).to eq([ games[1] ])
    end

    it "refuses a game that is not tied" do
      expect { cast("game_of_the_year", games[2], at: runoff_at) }
        .to raise_error(Voting::CastRules::GameNotInRunoffError)
    end

    it "refuses a runoff cast once the runoff was tallied" do
      allow(Voting::CastRules).to receive(:lock!).and_wrap_original do |original, *args|
        original.call(*args)
        GotyVote.where(year: 2026).update_all(runoff_closed_at: runoff_at)
      end

      expect { cast("game_of_the_year", games[0], at: runoff_at) }
        .to raise_error(Voting::CastRules::VotingClosedError, /runoff .* closed at/)
    end

    it "refuses an Award with no runoff" do
      gotm = candidates!("gotm", 2)

      expect { cast("gotm", gotm.first, at: runoff_at) }
        .to raise_error(Voting::CastRules::VotingClosedError, /no gotm runoff/)
    end
  end
end
