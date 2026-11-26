# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roadmap do
  describe ".set_positions!" do
    it "stamps updated_at in UTC whatever the session's time zone" do
      item = create(:roadmap_item, position: 1)
      ActiveRecord::Base.connection.execute("SET LOCAL TIME ZONE 'America/New_York'")

      described_class.set_positions!(RoadmapItem, { item.id => 2 })

      expect(item.reload.position).to eq(2)
      expect(item.updated_at).to be_within(1.minute).of(Time.current)
    end
  end
end
