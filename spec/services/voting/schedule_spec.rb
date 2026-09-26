# frozen_string_literal: true

require "rails_helper"

# The club calendar rules, ported from the bot's VoteDateUtils. Times are
# asserted in UTC so the US Eastern offset (and its DST change) is explicit.
RSpec.describe Voting::Schedule do
  describe ".default_closes_at" do
    it "ends at the end of the first Sunday after a Friday open" do
      friday_noon = Time.utc(2026, 7, 10, 16) # EDT
      expect(described_class.default_closes_at(friday_noon)).to be_within(1.second).of(Time.utc(2026, 7, 13, 3, 59, 59))
    end

    it "ends the same day when the vote opens on a Sunday" do
      sunday_noon = Time.utc(2026, 7, 12, 16)
      expect(described_class.default_closes_at(sunday_noon)).to be_within(1.second).of(Time.utc(2026, 7, 13, 3, 59, 59))
    end
  end

  describe ".next_opens_at" do
    it "is noon ET on the last Friday of the following month" do
      # From September 2026's vote, October 30 2026 (EDT, UTC-4).
      expect(described_class.next_opens_at(Time.utc(2026, 9, 25, 16))).to eq(Time.utc(2026, 10, 30, 16))
    end

    it "crosses into standard time and the new year" do
      # From November 2026 to December 25 2026 (EST, UTC-5).
      expect(described_class.next_opens_at(Time.utc(2026, 11, 27, 17))).to eq(Time.utc(2026, 12, 25, 17))
      # From December 2026 to January 29 2027.
      expect(described_class.next_opens_at(Time.utc(2026, 12, 25, 17))).to eq(Time.utc(2027, 1, 29, 17))
    end

    it "anchors on the previous round, not on when it was decided" do
      # A vote opened late in the month still schedules the next month.
      expect(described_class.next_opens_at(Time.utc(2026, 1, 31, 17))).to eq(Time.utc(2026, 2, 27, 17))
    end
  end

  describe ".month_label" do
    it "names the month after the vote, in US Eastern" do
      # 2026-10-01 02:00 UTC is still September 30 in New York.
      expect(described_class.month_label(Time.utc(2026, 10, 1, 2))).to eq("October 2026")
    end
  end

  describe ".reminder_at" do
    it "is 17:00 ET the given number of days before the open" do
      opens = Time.utc(2026, 10, 30, 16)
      expect(described_class.reminder_at(opens, 5)).to eq(Time.utc(2026, 10, 25, 21))
      expect(described_class.reminder_at(opens, 1)).to eq(Time.utc(2026, 10, 29, 21))
    end
  end
end
