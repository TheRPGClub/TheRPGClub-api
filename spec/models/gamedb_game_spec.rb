# frozen_string_literal: true

require "rails_helper"

RSpec.describe GamedbGame do
  it "stores a leading article at the end of the title, as IGDB imports do" do
    game = described_class.create!(title: "The Legend of Heroes: Trails in the Sky")

    expect(game.reload.title).to eq("Legend of Heroes: Trails in the Sky, The")
  end

  it "sorts article titles by their first significant word" do
    tag = SecureRandom.hex(4)
    [ "The #{tag} Last Guardian", "#{tag} Kingdom Hearts", "A #{tag} Hat in Time" ].each { |title| described_class.create!(title: title) }

    expect(described_class.where("title ILIKE ?", "%#{tag}%").order(:title).pluck(:title))
      .to eq([ "#{tag} Hat in Time, A", "#{tag} Kingdom Hearts", "#{tag} Last Guardian, The" ])
  end
end
