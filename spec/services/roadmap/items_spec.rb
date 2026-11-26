# frozen_string_literal: true

require "rails_helper"

# Roadmap::Items acts on the item as it stands under the Roadmap's write
# lock, not on a copy loaded before it (spec api#505).
RSpec.describe Roadmap::Items do
  let(:launch) { create(:roadmap_milestone, position: 1) }
  let(:later) { create(:roadmap_milestone, position: 2) }

  describe ".move!" do
    it "moves an item someone else moved since it was loaded" do
      item = create(:roadmap_item, milestone: launch, position: 1)
      stale = RoadmapItem.find(item.id)
      RoadmapItem.find(item.id).update!(milestone: later)

      described_class.move!(stale, launch.id, 1)

      expect(item.reload.milestone_id).to eq(launch.id)
      expect(item.position).to eq(1)
    end
  end

  describe ".ship!" do
    it "keeps the Shipped date of an item Shipped since it was loaded" do
      item = create(:roadmap_item, milestone: launch)
      stale = RoadmapItem.find(item.id)
      shipped_at = Time.zone.parse("2026-11-01 12:00")
      RoadmapItem.find(item.id).update!(shipped_at: shipped_at)

      described_class.ship!(stale)

      expect(item.reload.shipped_at).to eq(shipped_at)
      expect(stale.shipped_at).to eq(shipped_at)
    end
  end
end
