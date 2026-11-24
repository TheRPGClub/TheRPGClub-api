# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261124210000_store_completion_days_at_club_noon.rb")

# Legacy Game Completion days were stored at midnight UTC (or as the bot's
# full "now") and read as their UTC date. The migration moves each to noon
# club time of that UTC date, so the club day and the UTC date agree.
RSpec.describe StoreCompletionDaysAtClubNoon do
  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  def legacy(at)
    create(:completion).tap { |c| c.update_columns(completed_at: at) }
  end

  it "moves a midnight UTC day to noon club time of the same date" do
    midnight = legacy(Time.utc(2026, 11, 20))

    migrate_up

    stored = midnight.reload.completed_at
    expect(stored).to eq(ClubDay.noon(Date.new(2026, 11, 20)))
    expect(ClubDay.day_of(stored)).to eq(Date.new(2026, 11, 20))
  end

  it "keeps a full timestamp's UTC date (the day the export showed)" do
    evening = legacy(Time.utc(2026, 11, 25, 2, 30))

    migrate_up

    expect(evening.reload.completed_at).to eq(ClubDay.noon(Date.new(2026, 11, 25)))
  end

  it "leaves an unknown day null" do
    unknown = legacy(nil)

    migrate_up

    expect(unknown.reload.completed_at).to be_nil
  end
end
