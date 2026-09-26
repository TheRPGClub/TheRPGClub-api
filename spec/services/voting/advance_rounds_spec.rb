# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::AdvanceRounds do
  # Opens Friday 2026-10-30 noon ET; the 5-day reminder is due 2026-10-25 17:00
  # ET (21:00 UTC), the 1-day one 2026-10-29 17:00 ET; voting closes at the end
  # of Sunday 2026-11-01 ET.
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let!(:round) { create(:voting_round, voting_opens_at: opens_at) }

  def kinds
    VotingEvent.where(round_number: round.round_number).order(:id).pluck(:kind)
  end

  context "with automation off" do
    it "does nothing" do
      described_class.call(now: Time.utc(2026, 11, 3))

      expect(VotingEvent.count).to eq(0)
      expect(round.reload.closed_at).to be_nil
    end
  end

  context "with automation on" do
    before { allow(Voting).to receive(:automation_enabled?).and_return(true) }

    it "queues nothing before the first reminder is due" do
      described_class.call(now: Time.utc(2026, 10, 25, 20))

      expect(kinds).to be_empty
    end

    it "queues each nomination reminder once when due, expiring at the vote" do
      described_class.call(now: Time.utc(2026, 10, 25, 21))
      described_class.call(now: Time.utc(2026, 10, 26, 12))
      expect(kinds).to eq(%w[nomination_reminder_5d])

      described_class.call(now: Time.utc(2026, 10, 29, 21))
      expect(kinds).to eq(%w[nomination_reminder_5d nomination_reminder_1d])
      expect(VotingEvent.find_by(kind: "nomination_reminder_1d").expires_at).to eq(opens_at)
    end

    it "queues the vote panels once voting opens, expiring at the close" do
      described_class.call(now: opens_at + 1.minute)
      described_class.call(now: opens_at + 2.minutes)

      expect(kinds).to eq(%w[voting_opened])
      expect(VotingEvent.find_by(kind: "voting_opened").expires_at).to eq(round.voting_closes_at)
    end

    it "decides a closed round and queues the results and the decision" do
      nomination = create(:gotm_nomination, round_number: round.round_number)
      create(:gotm_vote, nomination: nomination)

      described_class.call(now: Time.utc(2026, 11, 3))

      expect(kinds).to eq(%w[voting_closed round_decided])
      expect(VotingEvent.find_by(kind: "round_decided").payload)
        .to eq("winners" => { "gotm" => [ nomination.gamedb_game_id ] }, "ties" => {})
      expect(VotingRound.current.round_number).to eq(round.round_number + 1)
    end

    it "queues a tie prompt instead of a decision when the lead is shared" do
      2.times { create(:gotm_vote, nomination: create(:gotm_nomination, round_number: round.round_number)) }

      described_class.call(now: Time.utc(2026, 11, 3))
      described_class.call(now: Time.utc(2026, 11, 3, 1))

      expect(kinds).to eq(%w[voting_closed tie_pending])
      expect(VotingRound.current).to eq(round)
    end
  end
end
