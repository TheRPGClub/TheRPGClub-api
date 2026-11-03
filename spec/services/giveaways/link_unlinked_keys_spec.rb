# frozen_string_literal: true

require "rails_helper"

RSpec.describe Giveaways::LinkUnlinkedKeys do
  let!(:unique_game) { create(:game, title: "Chrono Cross #{SecureRandom.hex(3)}") }
  let(:ambiguous_title) { "Doom #{SecureRandom.hex(3)}" }
  let(:unmatched_title) { "No Such Game #{SecureRandom.hex(6)}" }
  let!(:unique_keys) { create_list(:game_key, 2, game_title: unique_game.title.downcase) }
  let!(:ambiguous_key) { create(:game_key, game_title: ambiguous_title) }
  let!(:padded_ambiguous_key) { create(:game_key, game_title: " #{ambiguous_title} ") }
  let!(:unmatched_keys) { create_list(:game_key, 2, game_title: unmatched_title) }

  before do
    create(:game, title: ambiguous_title)
    create(:game, title: "#{ambiguous_title}!")
  end

  it "links only the keys whose title matches exactly one game, and reports the rest" do
    report = described_class.call

    expect(report.linked).to eq(2)
    expect(report.ambiguous).to eq(ambiguous_title => 2)
    expect(report.unmatched).to eq(unmatched_title => 2)
    expect(unique_keys.map { |key| key.reload.gamedb_game_id }).to all(eq(unique_game.game_id))
    expect(ambiguous_key.reload.gamedb_game_id).to be_nil
    expect(unmatched_keys.map { |key| key.reload.gamedb_game_id }).to all(be_nil)
  end

  it "never relinks a key that is already linked" do
    other = create(:game, title: "Manually Chosen #{SecureRandom.hex(3)}")
    linked = create(:game_key, game_title: unique_game.title, gamedb_game_id: other.game_id)

    described_class.call

    expect(linked.reload.gamedb_game_id).to eq(other.game_id)
  end

  it "writes nothing on a dry run but reports what it would link" do
    report = nil
    expect { report = described_class.call(dry_run: true) }
      .not_to(change { RpgClubGameKey.where.not(gamedb_game_id: nil).count })

    expect(report.linked).to eq(2)
    expect(report.unmatched).to eq(unmatched_title => 2)
  end
end
