# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::Providers do
  describe ".client_for" do
    it "returns each Provider's client" do
      expect(described_class.client_for("retroachievements")).to be_a(Retroachievements::Client)
      expect(described_class.client_for("steam")).to be_a(Steam::Client)
      expect(described_class.client_for(:psn)).to be_a(Psn::Client)
    end

    it "rejects an unknown Provider" do
      expect { described_class.client_for("xbox") }.to raise_error(ArgumentError, /xbox/)
    end
  end
end
