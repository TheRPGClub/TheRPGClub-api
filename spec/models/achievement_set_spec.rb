# frozen_string_literal: true

require "rails_helper"

RSpec.describe AchievementSet do
  it "is unique per Provider and external id" do
    existing = create(:achievement_set, provider: "psn")
    duplicate = build(:achievement_set, provider: "psn", external_id: existing.external_id)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(build(:achievement_set, provider: "steam", external_id: existing.external_id)).to be_valid
  end

  it "is unlinked, not deleted, when its GameDB game is deleted" do
    game = create(:game)
    set = create(:achievement_set, game: game)

    game.delete

    expect(set.reload.game_id).to be_nil
  end

  it "enqueues a GameDB link once it is created" do
    set = nil

    expect { set = create(:achievement_set) }.to have_enqueued_job(Achievements::LinkSetToGameJob)
    expect(Achievements::LinkSetToGameJob).to have_been_enqueued.with(set)
  end

  it "does not enqueue a GameDB link on update" do
    set = create(:achievement_set)

    expect { set.update!(title: "Renamed") }.not_to have_enqueued_job(Achievements::LinkSetToGameJob)
  end
end
