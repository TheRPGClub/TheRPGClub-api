# frozen_string_literal: true

require "rails_helper"

# The Challenges lifecycle job's schedule (ticket #379): it sweeps only when
# a step is due, so the minutes in between never touch the database, and it
# pauses while Challenges is Off. What the steps do is covered through the
# API in spec/requests/api/v1/behavior/challenge_lifecycle_spec.rb.
RSpec.describe Challenges::LifecycleJob do
  include ActiveSupport::Testing::TimeHelpers

  # A Season from 21 June to 22 September, created before it opens. Its
  # opening is due 2026-06-21 00:00 in the club's time zone (04:00 UTC).
  let(:opens_at) { Time.utc(2026, 6, 21, 4) }
  let!(:challenge) do
    travel_to(Time.utc(2026, 1, 2)) { create(:challenge, :seasonal, season: "06-21..09-22") }
  end

  before do
    set_feature_flag("challenges", "live")
    Challenges::SweepSchedule.clear
  end

  after { Challenges::SweepSchedule.clear }

  def perform_at(time)
    travel_to(time) { described_class.perform_now }
  end

  def season_openings = BotJob.where(kind: "challenge_announce").count { |job| job.payload["event"] == "season_opened" }

  it "sweeps once, then skips the database until the next step is due" do
    perform_at(Time.utc(2026, 6, 20))
    expect(Challenges::SweepSchedule.due?(Time.utc(2026, 6, 20, 0, 1))).to be(false)

    expect(Challenges::Lifecycle).not_to receive(:call)
    perform_at(Time.utc(2026, 6, 20, 0, 1))
  end

  it "sweeps when a step comes due, and then waits for the next one" do
    perform_at(opens_at - 7.hours)
    perform_at(opens_at - 1.minute)
    expect(season_openings).to eq(0)

    perform_at(opens_at)

    expect(season_openings).to eq(1)
    expect(Challenges::SweepSchedule.due?(opens_at + 1.minute)).to be(false)
  end

  it "runs no query at all in a minute with nothing due" do
    perform_at(Time.utc(2026, 6, 20))

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      perform_at(Time.utc(2026, 6, 20, 0, 1))
    end

    expect(queries).to be_empty
  end

  it "looks again by RECHECK when nothing is scheduled" do
    challenge.destroy!
    perform_at(Time.utc(2026, 6, 20))

    expect(Challenges::SweepSchedule.due?(Time.utc(2026, 6, 20, 1))).to be(false)
    expect(Challenges::SweepSchedule.due?(Time.utc(2026, 6, 20) + Challenges::SweepSchedule::RECHECK)).to be(true)
  end

  it "sweeps on the next minute after a Challenge changes" do
    perform_at(Time.utc(2026, 6, 1))

    challenge.update!(season_start_month: 6, season_start_day: 2)

    expect(Challenges::SweepSchedule.due?(Time.utc(2026, 6, 1, 0, 1))).to be(true)
  end

  context "while Challenges is Off" do
    before { set_feature_flag("challenges", "off") }

    it "takes no step when one comes due, and does not look again every minute" do
      perform_at(opens_at)

      expect(season_openings).to eq(0)
      expect(Challenges::SweepSchedule.due?(opens_at + 1.minute)).to be(false)
    end

    it "catches up on what fell due on the next minute after staff set it back on" do
      perform_at(opens_at)

      Features::ChangeFlag.call("challenges", "live", by: create(:user, role_admin: true).user_id)
      perform_at(opens_at + 1.minute)

      expect(season_openings).to eq(1)
    end
  end
end
