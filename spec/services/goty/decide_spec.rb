# frozen_string_literal: true

require "rails_helper"

# Deciding a GOTY Vote's Awards (spec api#471, ticket api#474): the GOTM
# round's steps (Voting::Decide) per Award, plus uncontested and empty
# Awards.
RSpec.describe Goty::Decide do
  let!(:vote) { create(:goty_vote, year: 2026, candidates_frozen_at: Time.utc(2027, 1, 15, 17)) }
  let(:after_close) { vote.voting_closes_at + 1.minute }

  def candidates!(award, count)
    create_list(:game, count).each_with_index.map do |game, position|
      GotyCandidate.create!(year: 2026, award: award, gamedb_game_id: game.game_id, position: position)
      game.game_id
    end
  end

  def votes!(award, game_id, count, runoff: false)
    create_list(:user, count).each do |user|
      GotyBallotVote.create!(year: 2026, award: award, user_id: user.user_id, gamedb_game_id: game_id, runoff: runoff)
    end
  end

  def winners
    GotyWinner.where(year: 2026).order(:award).pluck(:award, :gamedb_game_id, :decided_by)
  end

  describe ".close!" do
    it "records each Award's leader, an uncontested Award and no winner for an empty one, then decides" do
      gotm = candidates!("gotm", 3)
      votes!("gotm", gotm[1], 2)
      votes!("gotm", gotm[0], 1)
      only = candidates!("game_of_the_year", 1).first

      expect { expect(described_class.close!(vote, now: after_close)).to be(true) }
        .not_to have_enqueued_job(ShareCard::RefreshJob)

      expect(winners).to eq([ [ "game_of_the_year", only, "uncontested" ], [ "gotm", gotm[1], "vote" ] ])
      expect(vote.reload.phase(after_close)).to eq("decided")
    end

    it "lets one game win several Awards" do
      game = create(:game)
      %w[gotm game_of_the_year].each do |award|
        GotyCandidate.create!(year: 2026, award: award, gamedb_game_id: game.game_id, position: 0)
        candidates!(award, 1)
        votes!(award, game.game_id, 1)
      end

      described_class.close!(vote, now: after_close)

      expect(winners).to eq([ [ "game_of_the_year", game.game_id, "vote" ], [ "gotm", game.game_id, "vote" ] ])
    end

    it "opens one runoff for the tied Awards" do
      gotm = candidates!("gotm", 3)
      goty = candidates!("game_of_the_year", 3)
      votes!("gotm", gotm[0], 1)
      votes!("gotm", gotm[2], 1)
      votes!("game_of_the_year", goty[0], 2)
      votes!("game_of_the_year", goty[1], 2)
      nr = candidates!("nr_gotm", 2)
      votes!("nr_gotm", nr[0], 1)

      described_class.close!(vote, now: after_close)

      ties = { "gotm" => [ gotm[0], gotm[2] ].sort, "game_of_the_year" => goty.first(2).sort }
      expect(vote.reload).to have_attributes(pending_ties: ties, runoff_ties: ties, runoff_opens_at: after_close,
        runoff_closes_at: after_close + Voting.runoff_duration, decided_at: nil)
      expect(vote.phase(after_close)).to eq("runoff")
      expect(winners).to eq([ [ "nr_gotm", nr[0], "vote" ] ])
    end

    it "is a no-op the second time, and refuses while voting is open" do
      expect { described_class.close!(vote, now: vote.voting_opens_at + 1.hour) }
        .to raise_error(Voting::Decide::VotingNotClosedError)

      described_class.close!(vote, now: after_close)
      expect(described_class.close!(vote, now: after_close + 1.hour)).to be(false)
    end

    it "freezes the candidates first when the sweep has not" do
      vote.update!(candidates_frozen_at: nil)
      create(:gotm_entry, month_year: "May 2026", game: (game = create(:game)))

      described_class.close!(vote, now: after_close)

      expect(winners).to eq([ [ "gotm", game.game_id, "uncontested" ] ])
    end
  end

  describe ".close_runoff! and .resolve_tie!" do
    let(:gotm) { candidates!("gotm", 3) }
    let(:goty) { candidates!("game_of_the_year", 3) }
    let(:after_runoff) { vote.reload.runoff_closes_at + 1.minute }

    before do
      votes!("gotm", gotm[0], 1)
      votes!("gotm", gotm[1], 1)
      votes!("game_of_the_year", goty[0], 1)
      votes!("game_of_the_year", goty[1], 1)
      described_class.close!(vote, now: after_close)
    end

    it "decides the runoff's leaders" do
      votes!("gotm", gotm[1], 2, runoff: true)
      votes!("game_of_the_year", goty[0], 1, runoff: true)

      described_class.close_runoff!(vote, now: after_runoff)

      expect(winners).to eq([ [ "game_of_the_year", goty[0], "runoff" ], [ "gotm", gotm[1], "runoff" ] ])
      expect(vote.reload.phase(after_runoff)).to eq("decided")
    end

    it "leaves an Award that tied again pending for an admin, who settles it" do
      votes!("gotm", gotm[1], 1, runoff: true)
      votes!("game_of_the_year", goty[0], 1, runoff: true)
      votes!("game_of_the_year", goty[1], 1, runoff: true)

      described_class.close_runoff!(vote, now: after_runoff)

      expect(vote.reload.pending_ties).to eq("game_of_the_year" => goty.first(2).sort)
      expect(vote.phase(after_runoff)).to eq("tie")

      decided = nil
      expect do
        decided = described_class.resolve_tie!(vote, award: "game_of_the_year", gamedb_game_id: goty[1],
          now: after_runoff + 1.hour)
      end.not_to have_enqueued_job(ShareCard::RefreshJob)

      expect(decided).to be(true)
      expect(winners).to eq([ [ "game_of_the_year", goty[1], "admin" ], [ "gotm", gotm[1], "runoff" ] ])
      expect(vote.reload.phase).to eq("decided")
    end

    it "refuses a pick that is not tied, or an Award with no tie" do
      expect { described_class.resolve_tie!(vote, award: "gotm", gamedb_game_id: gotm[2]) }
        .to raise_error(Voting::Decide::InvalidPickError)
      expect { described_class.resolve_tie!(vote, award: "nr_gotm", gamedb_game_id: gotm[0]) }
        .to raise_error(Voting::Decide::NoTieError, /GOTY Vote 2026 has no pending nr_gotm tie/)
    end

    it "lets an admin settle an Award while its runoff is open" do
      described_class.resolve_tie!(vote, award: "gotm", gamedb_game_id: gotm[0], now: after_close + 1.hour)

      expect(vote.reload.pending_ties.keys).to eq([ "game_of_the_year" ])
      expect(vote.phase(after_close + 1.hour)).to eq("runoff")
      expect(winners).to eq([ [ "gotm", gotm[0], "admin" ] ])
    end
  end
end
