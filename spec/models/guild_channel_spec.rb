# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuildChannel do
  describe ".text_channel?" do
    it "accepts a synced text or announcement channel" do
      create(:guild_channel, channel_id: "1", channel_type: 0)
      create(:guild_channel, channel_id: "2", channel_type: 5)

      expect(described_class.text_channel?("1")).to be(true)
      expect(described_class.text_channel?(2)).to be(true)
    end

    it "rejects voice channels, categories, unknown ids and blanks" do
      create(:guild_channel, channel_id: "3", channel_type: 2)
      create(:guild_channel, channel_id: "4", channel_type: 4)

      expect(described_class.text_channel?("3")).to be(false)
      expect(described_class.text_channel?("4")).to be(false)
      expect(described_class.text_channel?("5")).to be(false)
      expect(described_class.text_channel?(nil)).to be(false)
    end
  end
end
