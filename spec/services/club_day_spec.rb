# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClubDay do
  # 21:30 club time on the 24th is 02:30 UTC on the 25th (a club evening).
  let(:club_evening) { Time.utc(2026, 11, 25, 2, 30) }

  describe ".noon" do
    it "is 12:00 club time, the same UTC date and the same club day" do
      noon = described_class.noon(Date.new(2026, 11, 24))

      expect(noon.utc).to eq(Time.utc(2026, 11, 24, 17))
      expect(noon.utc.to_date).to eq(Date.new(2026, 11, 24))
      expect(described_class.day_of(noon)).to eq(Date.new(2026, 11, 24))
    end

    it "holds across daylight saving time" do
      expect(described_class.noon(Date.new(2026, 7, 4)).utc).to eq(Time.utc(2026, 7, 4, 16))
    end
  end

  describe ".day_of" do
    it "is the club day of a moment, not its UTC date" do
      expect(described_class.day_of(club_evening)).to eq(Date.new(2026, 11, 24))
    end

    it "is nil for nil" do
      expect(described_class.day_of(nil)).to be_nil
    end
  end

  describe ".day_named" do
    it "reads a date-only string or a Date as that date" do
      expect(described_class.day_named("2026-11-25")).to eq(Date.new(2026, 11, 25))
      expect(described_class.day_named(Date.new(2026, 11, 25))).to eq(Date.new(2026, 11, 25))
    end

    it "reads a full timestamp as its club day" do
      expect(described_class.day_named(club_evening)).to eq(Date.new(2026, 11, 24))
      expect(described_class.day_named("2026-11-25T02:30:00Z")).to eq(Date.new(2026, 11, 24))
    end

    it "is nil for blank or unreadable values" do
      expect(described_class.day_named(nil)).to be_nil
      expect(described_class.day_named("")).to be_nil
      expect(described_class.day_named("not a date")).to be_nil
      expect(described_class.day_named("2026-13-45")).to be_nil
    end
  end
end
