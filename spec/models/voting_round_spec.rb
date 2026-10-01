# frozen_string_literal: true

require "rails_helper"

RSpec.describe VotingRound do
  # Friday 2026-10-30 12:00 ET (EDT) is 16:00 UTC; the default close is the end
  # of Sunday 2026-11-01 ET, which is after the DST change (EST, UTC-5).
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let(:default_close) { Time.utc(2026, 11, 2, 4, 59, 59) }
  let(:base) { (SecureRandom.random_number(1_000_000) * 10) + 1_000 }

  describe "schedule defaults" do
    it "closes at the end of the weekend's Sunday and labels the following month" do
      round = create(:voting_round, voting_opens_at: opens_at)

      expect(round.voting_closes_at).to be_within(1.second).of(default_close)
      expect(round.month_year).to eq("November 2026")
    end

    it "keeps an explicit close" do
      close = opens_at + 1.day
      round = create(:voting_round, voting_opens_at: opens_at, voting_closes_at: close)

      expect(round.voting_closes_at).to eq(close)
    end

    it "moves the default close with the open when only the open is rescheduled" do
      round = create(:voting_round, voting_opens_at: opens_at)
      round.update!(voting_opens_at: opens_at + 7.days)

      expect(round.voting_closes_at).to be_within(1.second).of(default_close + 7.days)
    end

    it "rejects a close before the open" do
      round = build(:voting_round, voting_opens_at: opens_at, voting_closes_at: opens_at - 1.hour)

      expect(round).not_to be_valid
    end
  end

  describe "#phase" do
    let(:round) { create(:voting_round, voting_opens_at: opens_at) }

    it "walks nominating -> voting -> closed across the window" do
      expect(round.phase(opens_at - 1.second)).to eq("nominating")
      expect(round.phase(opens_at)).to eq("voting")
      expect(round.phase(default_close - 1.second)).to eq("voting")
      expect(round.phase(default_close + 1.second)).to eq("closed")
    end

    it "reports a closed round with shared leads as tied" do
      round.update!(closed_at: default_close, pending_ties: { "gotm" => [ 1, 2 ] })

      expect(round.phase(default_close + 1.hour)).to eq("tie")
      expect(round.voting_ended?(default_close + 1.hour)).to be(true)
    end

    context "with a runoff" do
      let(:runoff_closes) { default_close + 1.day }

      before do
        round.update!(closed_at: default_close, pending_ties: { "gotm" => [ 1, 2 ] },
          runoff_ties: { "gotm" => [ 1, 2 ] }, runoff_opens_at: default_close, runoff_closes_at: runoff_closes)
      end

      it "is in its runoff until the runoff closes, then closed until it is tallied" do
        expect(round.phase(runoff_closes - 1.second)).to eq("runoff")
        expect(round.runoff_open?(runoff_closes - 1.second)).to be(true)
        expect(round.voting_ended?(runoff_closes - 1.second)).to be(true)
        expect(round.runoff_ended?(runoff_closes - 1.second)).to be(false)

        expect(round.phase(runoff_closes)).to eq("closed")
        expect(round.runoff_ended?(runoff_closes)).to be(true)
      end

      it "is tied when the tallied runoff left a tie, and closed when it did not" do
        round.update!(runoff_closed_at: runoff_closes)
        expect(round.phase(runoff_closes + 1.hour)).to eq("tie")

        round.update!(pending_ties: {})
        expect(round.phase(runoff_closes + 1.hour)).to eq("closed")
      end

      it "keeps runoff votes hidden only while the runoff is open" do
        expect(described_class.ended?(round.round_number, runoff_closes - 1.second)).to be(true)
        expect(described_class.ended?(round.round_number, runoff_closes - 1.second, runoff: true)).to be(false)
        expect(described_class.ended?(round.round_number, runoff_closes, runoff: true)).to be(true)
      end

      it "rejects a runoff that closes before it opens" do
        round.runoff_closes_at = default_close - 1.minute

        expect(round).not_to be_valid
      end
    end

    it "is decided once decided_at is set, whatever the clock says" do
      round.update!(decided_at: opens_at - 1.day)

      expect(round.phase(opens_at - 2.days)).to eq("decided")
      expect(round.nominations_open?(opens_at - 2.days)).to be(false)
    end
  end

  describe ".current" do
    it "is the lowest undecided round" do
      create(:voting_round, round_number: base, voting_opens_at: opens_at - 30.days, decided_at: opens_at - 20.days)
      current = create(:voting_round, round_number: base + 1, voting_opens_at: opens_at)

      expect(described_class.current).to eq(current)
    end
  end

  describe ".nominations_open_for?" do
    before { create(:voting_round, round_number: base, voting_opens_at: opens_at) }

    it "is open for the current round until its vote opens" do
      expect(described_class.nominations_open_for?(base, opens_at - 1.second)).to be(true)
      expect(described_class.nominations_open_for?(base.to_s, opens_at - 1.second)).to be(true)
      expect(described_class.nominations_open_for?(base, opens_at)).to be(false)
    end

    it "is closed for any other round" do
      expect(described_class.nominations_open_for?(base + 1, opens_at - 1.day)).to be(false)
      expect(described_class.nominations_open_for?(base - 1, opens_at - 1.day)).to be(false)
    end
  end

  describe ".ended?" do
    before { create(:voting_round, round_number: base, voting_opens_at: opens_at) }

    it "follows the round's own window" do
      expect(described_class.ended?(base, opens_at)).to be(false)
      expect(described_class.ended?(base, default_close + 1.second)).to be(true)
    end

    it "treats rounds before the current one as ended, row or not" do
      expect(described_class.ended?(base - 5, opens_at)).to be(true)
      expect(described_class.ended?(base + 5, opens_at)).to be(false)
    end
  end

  describe "#decide!" do
    it "stamps the round and schedules the next one for the last Friday of the following month" do
      round = create(:voting_round, round_number: base, voting_opens_at: opens_at)
      now = default_close + 1.minute

      round.decide!(now)

      expect(round.reload).to have_attributes(closed_at: now, decided_at: now, pending_ties: {})
      following = described_class.find(base + 1)
      # Last Friday of November 2026 is the 27th; noon EST is 17:00 UTC.
      expect(following.voting_opens_at).to eq(Time.utc(2026, 11, 27, 17))
      expect(described_class.current).to eq(following)
    end

    it "is idempotent and never reschedules an existing next round" do
      round = create(:voting_round, round_number: base, voting_opens_at: opens_at)
      following = create(:voting_round, round_number: base + 1, voting_opens_at: opens_at + 40.days)

      round.decide!(default_close + 1.minute)
      round.decide!(default_close + 2.minutes)

      expect(following.reload.voting_opens_at).to be_within(1.second).of(opens_at + 40.days)
      expect(round.reload.decided_at).to eq(default_close + 1.minute)
    end
  end
end
