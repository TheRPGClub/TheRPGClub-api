# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261117140000_add_date_precision_to_gamedb_releases.rb")

# api#392: a Release's date becomes a plain calendar date and every Release
# gets a Date Precision. Existing Releases keep the calendar day of their UTC
# timestamp and read as `day`; one with no date at all reads as `tba`.
RSpec.describe AddDatePrecisionToGamedbReleases do
  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    GamedbRelease.reset_column_information
  end

  def insert_release(release_date)
    # Raw SQL: the model's Date Precision enum needs the column this rolled back.
    GamedbRelease.connection.select_value(<<~SQL.squish)
      INSERT INTO gamedb_releases (game_id, platform_id, region_id, release_date)
      VALUES (#{create(:game).game_id}, #{create(:platform).platform_id}, #{create(:region).region_id},
              #{release_date ? GamedbRelease.connection.quote(release_date) : "NULL"})
      RETURNING release_id
    SQL
  end

  after { GamedbRelease.reset_column_information }

  it "keeps each existing Release's UTC calendar day and reads it as `day`" do
    migrate(:down)
    midnight = insert_release("2031-06-01 00:00:00")
    late_evening = insert_release("2031-06-01 23:30:00")

    migrate(:up)

    expect(GamedbRelease.find(midnight)).to have_attributes(release_date: Date.new(2031, 6, 1), date_precision: "day")
    expect(GamedbRelease.find(late_evening)).to have_attributes(release_date: Date.new(2031, 6, 1), date_precision: "day")
  end

  it "reads an existing Release with no date as `tba`" do
    migrate(:down)
    undated = insert_release(nil)

    migrate(:up)

    expect(GamedbRelease.find(undated)).to have_attributes(release_date: nil, date_precision: "tba")
  end
end
