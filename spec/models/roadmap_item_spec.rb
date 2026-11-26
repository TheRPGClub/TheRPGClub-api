# frozen_string_literal: true

require "rails_helper"

# A Roadmap Item (GLOSSARY "Roadmap Item"; spec api#505).
RSpec.describe RoadmapItem do
  let(:milestone) { RoadmapMilestone.create!(name: "Launch", position: 1) }

  def item(**attrs) = described_class.new(milestone: milestone, title: "Roadmap", blurb: "A page.", position: 1, **attrs)

  it "takes an optional area of bot, website or both" do
    expect(item).to be_valid
    expect(item(area: "both")).to be_valid
    expect(item(area: "discord")).not_to be_valid
  end

  it "takes only a GitHub issue URL" do
    expect(item(github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-api/issues/505")).to be_valid
    expect(item(github_issue_url: "https://example.com/issues/1")).not_to be_valid
    expect(item(github_issue_url: "https://github.com/TheRPGClub/TheRPGClub-api/pull/1")).not_to be_valid
  end

  it "needs a title, a blurb and a Milestone" do
    expect(item(title: "")).not_to be_valid
    expect(item(blurb: "")).not_to be_valid
    expect(described_class.new(title: "A", blurb: "B", position: 1)).not_to be_valid
  end

  it "is Shipped once it has a Shipped date" do
    expect(item).not_to be_shipped
    expect(item(shipped_at: Time.current)).to be_shipped
  end
end
