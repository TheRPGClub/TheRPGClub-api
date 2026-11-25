# frozen_string_literal: true

require "rails_helper"

# The GOTY Vote's schedule and derived phase (spec api#471). Times are
# asserted in UTC so the US Eastern offset is explicit.
RSpec.describe GotyVote do
  describe "default schedule" do
    it "opens nominations on January 1 and votes on the first weekend from January 15 (ET)" do
      vote = described_class.new(year: 2026)
      vote.validate

      expect(vote.nominations_open_at).to eq(Time.utc(2027, 1, 1, 5))  # 00:00 EST
      expect(vote.voting_opens_at).to eq(Time.utc(2027, 1, 15, 17))    # Friday 12:00 EST
      expect(vote.voting_closes_at).to be_within(1.second).of(Time.utc(2027, 1, 18, 4, 59, 59)) # end of Sunday
    end

    it "takes the first Friday after January 15 when the 15th is not a Friday" do
      # January 15 2028 is a Saturday; the first Friday on or after it is the 21st.
      vote = described_class.new(year: 2027)
      vote.validate

      expect(vote.voting_opens_at).to eq(Time.utc(2028, 1, 21, 17))
      expect(vote.voting_closes_at).to be_within(1.second).of(Time.utc(2028, 1, 24, 4, 59, 59))
    end

    it "keeps the default weekend when only the voting open is moved" do
      vote = described_class.create!(year: 2026)
      vote.update!(voting_opens_at: Time.utc(2027, 1, 22, 17))

      expect(vote.voting_closes_at).to be_within(1.second).of(Time.utc(2027, 1, 25, 4, 59, 59))
    end

    it "refuses dates out of order" do
      vote = described_class.new(year: 2026, nominations_open_at: Time.utc(2027, 1, 20), voting_opens_at: Time.utc(2027, 1, 15, 17))

      expect(vote).not_to be_valid
      expect(vote.errors[:voting_opens_at]).to be_present
    end
  end

  describe ".ensure!" do
    it "creates the year's GOTY Vote once with its default schedule" do
      first = described_class.ensure!(2026)
      again = described_class.ensure!(2026)

      expect(again).to eq(first)
      expect(first.voting_opens_at).to eq(Time.utc(2027, 1, 15, 17))
    end
  end

  describe "#phase" do
    let(:vote) { described_class.new(year: 2026).tap(&:validate) }

    it "moves upcoming -> nominating -> voting -> closed with the default dates" do
      expect(vote.phase(Time.utc(2026, 12, 31, 12))).to eq("upcoming")
      expect(vote.phase(Time.utc(2027, 1, 1, 5))).to eq("nominating")
      expect(vote.phase(Time.utc(2027, 1, 15, 16, 59))).to eq("nominating")
      expect(vote.phase(Time.utc(2027, 1, 15, 17))).to eq("voting")
      expect(vote.phase(Time.utc(2027, 1, 18, 5))).to eq("closed")
    end

    it "follows a moved date" do
      vote = described_class.create!(year: 2026)
      vote.update!(voting_opens_at: Time.utc(2027, 1, 22, 17))

      expect(vote.phase(Time.utc(2027, 1, 16))).to eq("nominating")
      expect(vote.phase(Time.utc(2027, 1, 23))).to eq("voting")
    end

    it "is runoff while the runoff window is open, then tie while an Award is still pending" do
      closed = Time.utc(2027, 1, 18, 5)
      vote.assign_attributes(closed_at: closed, runoff_opens_at: closed, runoff_closes_at: closed + 1.day,
        pending_ties: { "gotm" => [ 1, 2 ] }, runoff_ties: { "gotm" => [ 1, 2 ] })

      expect(vote.phase(closed + 1.hour)).to eq("runoff")
      expect(vote.phase(closed + 2.days)).to eq("closed") # the runoff's tally is not in yet

      vote.runoff_closed_at = closed + 1.day
      expect(vote.phase(closed + 2.days)).to eq("tie")
    end

    it "is decided once decided_at is set, whatever the dates say" do
      vote.decided_at = Time.utc(2027, 1, 18, 5)

      expect(vote.phase(Time.utc(2027, 1, 18, 6))).to eq("decided")
    end
  end
end
