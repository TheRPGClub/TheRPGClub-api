# frozen_string_literal: true

require "rails_helper"

# Fixtures ported from the bot: resolveGameCompletionPlatformId (numeric id,
# then exact name/abbreviation/code, then a unique partial match),
# resolveCsvPlatformId (GAMEDB_CSV_PLATFORM_MAP first) and the Completionator
# resolvePlatformId (mapped names onto a given platform set).
RSpec.describe Imports::PlatformResolver do
  subject(:resolver) { described_class.new }

  let!(:windows) { create(:platform, platform_name: "Windows", platform_abbreviation: "PC", platform_code: "WIN") }
  let!(:ps4) { create(:platform, platform_name: "PlayStation 4", platform_abbreviation: "PS4", platform_code: "PS4") }
  let!(:ps5) { create(:platform, platform_name: "PlayStation 5", platform_abbreviation: "PS5", platform_code: "PS5") }
  let!(:psp) { create(:platform, platform_name: "PlayStation Portable", platform_abbreviation: "PSP", platform_code: "PSPX") }
  let!(:steam) { create(:platform, platform_name: "Steam", platform_code: "STEAM") }

  describe "#resolve_direct" do
    it "accepts an existing numeric id" do
      expect(resolver.resolve_direct(" #{ps4.platform_id} ")).to eq(ps4.platform_id)
    end

    it "rejects an unknown numeric id" do
      expect(resolver.resolve_direct((GamedbPlatform.maximum(:platform_id) + 1).to_s)).to be_nil
    end

    it "matches the name, abbreviation or code exactly, ignoring case" do
      expect(resolver.resolve_direct("windows")).to eq(windows.platform_id)
      expect(resolver.resolve_direct("ps5")).to eq(ps5.platform_id)
      expect(resolver.resolve_direct("pspx")).to eq(psp.platform_id)
    end

    it "accepts a unique partial match" do
      expect(resolver.resolve_direct("Portable")).to eq(psp.platform_id)
    end

    it "rejects an ambiguous partial match" do
      expect(resolver.resolve_direct("PlayStation")).to be_nil
    end

    it "returns nil for blank input" do
      expect(resolver.resolve_direct(" ")).to be_nil
      expect(resolver.resolve_direct(nil)).to be_nil
    end
  end

  describe "#resolve" do
    it "resolves a mapped label through the platform map" do
      expect(resolver.resolve("PC / Windows")).to eq(windows.platform_id)
    end

    it "collapses whitespace and case in the map key" do
      expect(resolver.resolve("  PlayStation   4 ")).to eq(ps4.platform_id)
    end

    it "resolves a mapped name that is an abbreviation rather than a platform name" do
      expect(resolver.mapped_names("psp")).to eq([ "PSP" ])
      expect(resolver.resolve("psp")).to eq(psp.platform_id)
    end

    it "falls back to direct resolution for unmapped labels" do
      expect(resolver.resolve("Steam")).to eq(steam.platform_id)
    end

    it "returns nil when nothing resolves" do
      expect(resolver.resolve("Commodore 64")).to be_nil
    end
  end

  describe "#resolve_mapped" do
    it "maps the label onto the given platforms by name" do
      expect(resolver.resolve_mapped("PC", among: [ ps4, windows ])).to eq(windows.platform_id)
    end

    it "returns nil when the mapped platform is not among the given ones" do
      expect(resolver.resolve_mapped("PC", among: [ ps4 ])).to be_nil
    end

    it "returns nil for unmapped labels" do
      expect(resolver.resolve_mapped("Windows 95", among: [ windows ])).to be_nil
    end
  end

  describe "the platform map" do
    it "carries every entry of the bot's GAMEDB_CSV_PLATFORM_MAP" do
      expect(described_class::PLATFORM_MAP.size).to eq(68)
      expect(described_class::PLATFORM_MAP["xbox series x|s"]).to eq([ "Xbox Series X|S" ])
      expect(described_class::PLATFORM_MAP["nintendo switch 2"]).to eq([ "Switch 2" ])
    end
  end
end
