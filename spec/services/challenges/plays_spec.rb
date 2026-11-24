# frozen_string_literal: true

require "rails_helper"

# Challenges read a Game Completion's day and a Now Playing start through the
# one day rule (ClubDay.day_of), so they agree with the website and export.
RSpec.describe Challenges::Plays do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it "dates a completion logged on a club evening on that club day, as written" do
    travel_to(Time.utc(2026, 11, 25, 2, 30)) do # 21:30 club time on the 24th
      create(:completion, user:, completed_at: Time.current)
      create(:completion, user:, completed_at: "2026-11-23")
    end

    expect(described_class.of(user.user_id).completions.map(&:last))
      .to eq([ Date.new(2026, 11, 23), Date.new(2026, 11, 24) ])
  end

  it "dates a Now Playing start by its club day" do
    entry = create(:now_playing_entry, user:)
    entry.update_columns(added_at: Time.utc(2026, 11, 25, 2, 30))

    expect(described_class.of(user.user_id).now_playing).to eq([ [ entry.gamedb_game_id, Date.new(2026, 11, 24) ] ])
  end
end
