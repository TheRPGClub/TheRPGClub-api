# frozen_string_literal: true

require "rails_helper"
require "rake"

# The one-off deploy step for the Release Calendar (api#389 review #2): right
# after the migrations, `bin/rails gamedb:refresh_releases` runs the weekly
# IGDB refresh once, so Releases backfilled as `day` are corrected before the
# first Monday run. The selection and the sync are the job's; this only checks
# that the task runs it, and can run it again.
RSpec.describe "gamedb:refresh_releases" do # rubocop:disable RSpec/DescribeClass
  let(:refreshed) { [] }
  let(:importer) { instance_double(Gamedb::IgdbGameImporter) }
  let(:task) { Rake::Task["gamedb:refresh_releases"] }

  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("gamedb:refresh_releases") }

  around do |example|
    original_pause = Gamedb::ReleaseRefreshJob.pause_seconds
    Gamedb::ReleaseRefreshJob.pause_seconds = 0
    example.run
  ensure
    Gamedb::ReleaseRefreshJob.pause_seconds = original_pause
  end

  before do
    allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
    allow(importer).to receive(:refresh_releases!) { |game_id| refreshed << game_id }
    task.reenable
  end

  it "refreshes every game the weekly refresh would, now, and can be run again" do
    upcoming = create(:game, igdb_id: 101)
    create(:release, game: upcoming, release_date: Time.current.utc.to_date + 30, date_precision: "day")
    past = create(:game, igdb_id: 102)
    create(:release, game: past, release_date: Time.current.utc.to_date - 400, date_precision: "day")

    expect { task.invoke }.to output(/Refreshed the Releases of 1 game/).to_stdout
    task.reenable
    expect { task.invoke }.to output(/Refreshed the Releases of 1 game/).to_stdout

    expect(refreshed).to eq([ upcoming.game_id, upcoming.game_id ])
  end
end
