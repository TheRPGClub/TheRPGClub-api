# frozen_string_literal: true

require "rails_helper"

# A Milestone (GLOSSARY "Milestone"; spec api#505): its target date is known
# to a Date Precision, TBA (no date) by default, and a vague date is stored on
# the first day of its period, as a Release's is.
RSpec.describe RoadmapMilestone do
  it "is TBA with no date by default" do
    milestone = described_class.create!(name: "In The Future", position: 1)

    expect(milestone).to have_attributes(date_precision: "tba", target_date: nil, reached_at: nil)
    expect(milestone).not_to be_reached
  end

  it "stores a vague target date on the first day of its period" do
    month = described_class.create!(name: "Launch", position: 1, target_date: Date.new(2026, 12, 18),
      date_precision: "month")
    quarter = described_class.create!(name: "After", position: 2, target_date: Date.new(2027, 2, 10),
      date_precision: "quarter")
    year = described_class.create!(name: "Later", position: 3, target_date: Date.new(2028, 7, 4),
      date_precision: "year")

    expect([ month, quarter, year ].map(&:target_date))
      .to eq([ Date.new(2026, 12, 1), Date.new(2027, 1, 1), Date.new(2028, 1, 1) ])
  end

  it "needs a date for any precision but TBA, and none for TBA" do
    expect(described_class.new(name: "A", position: 1, date_precision: "day")).not_to be_valid
    expect(described_class.new(name: "A", position: 1, date_precision: "tba", target_date: Date.new(2027, 1, 1)))
      .not_to be_valid
  end

  it "refuses an unknown precision, a blank name and a position below 1" do
    expect(described_class.new(name: "A", position: 1, date_precision: "week")).not_to be_valid
    expect(described_class.new(name: " ", position: 1)).not_to be_valid
    expect(described_class.new(name: "A", position: 0)).not_to be_valid
  end

  it "can't be deleted from the database while it has Roadmap Items" do
    milestone = described_class.create!(name: "Launch", position: 1)
    RoadmapItem.create!(milestone: milestone, title: "Roadmap", blurb: "A page.", position: 1)

    expect { milestone.delete }.to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
