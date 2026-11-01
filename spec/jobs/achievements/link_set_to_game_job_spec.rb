# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::LinkSetToGameJob do
  it "links the Achievement Set to its GameDB game" do
    title = "Hollow Knight #{SecureRandom.hex(3)}"
    game = create(:game, title: title)
    set = create(:achievement_set, provider: "psn", title: title)

    described_class.perform_now(set)

    expect(set.reload.game_id).to eq(game.game_id)
  end
end
