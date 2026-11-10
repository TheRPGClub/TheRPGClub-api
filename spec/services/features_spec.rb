# frozen_string_literal: true

require "rails_helper"

# The Feature registry (spec #347): what staff see listed on the flags page
# and what every access decision is keyed by.
RSpec.describe Features do
  it "names what each Feature covers on the website, in the bot and in automated posts" do
    expect(described_class.all).to all(
      have_attributes(coverage: match(website: be_an(Array), bot: be_an(Array), posts: be_an(Array)))
    )
    expect(described_class.all.map { |feature| feature.coverage[:website] }).to all(be_present)
    expect(described_class.fetch("giveaways").coverage).to eq(
      website: [ "Giveaways", "Donate", "Your claimed keys" ],
      bot: [ "/giveaway" ],
      posts: [ "Giveaway hub", "Giveaway claim notices" ]
    )
  end

  it "has six Core Features and five hideable ones" do
    expect(described_class.all.select(&:core?).map(&:key))
      .to eq(%w[game_index voting_gotm backlog collection now_playing game_completions])
    expect(described_class.all.select(&:hideable?).map(&:key))
      .to eq(%w[reviews achievement_hub giveaways journals suggestions])
  end

  it "does not know things that are not Features" do
    expect(described_class.known?("dashboard")).to be(false)
    expect { described_class.fetch("dashboard") }.to raise_error(KeyError)
  end
end
