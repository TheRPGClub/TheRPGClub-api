# frozen_string_literal: true

require "rails_helper"
require "fugit"

# The weekly IGDB refresh (api#393, ADR 0010): which GameDB games it picks and
# that one game failing does not stop the rest. The in-place sync itself is
# covered through POST /games/:id/refresh-releases, so the importer is faked
# here and only records the games it was asked to refresh.
RSpec.describe Gamedb::ReleaseRefreshJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:today) { Date.new(2027, 5, 15) }
  let(:refreshed) { [] }
  let(:importer) { instance_double(Gamedb::IgdbGameImporter) }

  around do |example|
    original_pause = described_class.pause_seconds
    described_class.pause_seconds = 0
    travel_to(today.in_time_zone("UTC").change(hour: 9)) { example.run }
  ensure
    described_class.pause_seconds = original_pause
  end

  before do
    allow(Gamedb::IgdbGameImporter).to receive(:new).and_return(importer)
    allow(importer).to receive(:refresh_releases!) { |game_id| refreshed << game_id }
  end

  def game_with_releases(*releases, **attributes)
    create(:game, igdb_id: SecureRandom.random_number(1_000_000_000), **attributes).tap do |game|
      releases.each do |date, precision|
        create(:release, game: game, release_date: date, date_precision: precision || "day")
      end
    end
  end

  it "refreshes a game with a Release dated today or later, and leaves a game with only past Releases alone" do
    releasing_today = game_with_releases([ today ])
    releasing_later = game_with_releases([ today - 1.year ], [ today + 3.months ])
    game_with_releases([ today - 1.day ], [ today - 2.years ])

    described_class.perform_now

    expect(refreshed).to contain_exactly(releasing_today.game_id, releasing_later.game_id)
  end

  it "refreshes a game with a month, quarter or year Release until that whole period has ended" do
    this_month = game_with_releases([ Date.new(2027, 5, 1), "month" ])
    this_quarter = game_with_releases([ Date.new(2027, 4, 1), "quarter" ])
    this_year = game_with_releases([ Date.new(2027, 1, 1), "year" ])
    game_with_releases([ Date.new(2027, 4, 1), "month" ])
    game_with_releases([ Date.new(2027, 1, 1), "quarter" ])
    game_with_releases([ Date.new(2026, 1, 1), "year" ])

    described_class.perform_now

    expect(refreshed).to contain_exactly(this_month.game_id, this_quarter.game_id, this_year.game_id)
  end

  it "refreshes a game with a TBA Release, even beside past Releases" do
    tba = game_with_releases([ today - 3.years ], [ nil, "tba" ])

    described_class.perform_now

    expect(refreshed).to contain_exactly(tba.game_id)
  end

  it "refreshes a game with no Releases unless its first release date is past" do
    undated = game_with_releases
    first_release_ahead = game_with_releases(initial_release_date: Time.utc(2027, 9, 1))
    first_release_today = game_with_releases(initial_release_date: Time.utc(2027, 5, 15))
    game_with_releases(initial_release_date: Time.utc(2027, 5, 14, 23))

    described_class.perform_now

    expect(refreshed).to contain_exactly(undated.game_id, first_release_ahead.game_id, first_release_today.game_id)
  end

  it "skips games without an IGDB id, however upcoming their Releases" do
    game_with_releases([ today + 1.month ], [ nil, "tba" ], igdb_id: nil)
    game_with_releases(igdb_id: nil)

    described_class.perform_now

    expect(refreshed).to be_empty
  end

  it "logs a game that fails to refresh and carries on with the rest" do
    first, failing, last = Array.new(3) { game_with_releases([ today + 1.week ]) }
    allow(importer).to receive(:refresh_releases!).with(failing.game_id)
      .and_raise(Igdb::Client::RequestError, "IGDB games request failed with HTTP 500")
    allow(Rails.logger).to receive(:error)

    described_class.perform_now

    expect(refreshed).to contain_exactly(first.game_id, last.game_id)
    expect(Rails.logger).to have_received(:error)
      .with(a_string_including("Game #{failing.game_id}", "IGDB games request failed with HTTP 500"))
  end

  it "stops the run when IGDB is not configured, instead of failing every game" do
    2.times { game_with_releases([ today + 1.week ]) }
    allow(importer).to receive(:refresh_releases!)
      .and_raise(Igdb::Client::ConfigurationError, "IGDB_CLIENT_ID must be set")

    expect { described_class.perform_now }
      .to raise_error(Igdb::Client::ConfigurationError, "IGDB_CLIENT_ID must be set")
    expect(importer).to have_received(:refresh_releases!).once
  end

  it "is scheduled once a week in production" do
    task = YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result)
      .fetch("production").values.find { |entry| entry["class"] == described_class.name }
    cron = Fugit.parse(task.fetch("schedule"))
    first = cron.next_time(Time.utc(2027, 5, 1)).to_t.utc
    runs = [ first ]
    runs << cron.next_time(runs.last).to_t.utc while runs.size < 3

    expect(runs.each_cons(2).map { |earlier, later| later - earlier }).to eq([ 1.week, 1.week ])
  end
end
