# frozen_string_literal: true

require "rails_helper"
require "fugit"

RSpec.describe "Achievement sync scheduling" do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  describe "config/recurring.yml" do
    let(:tasks) { YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result).fetch("production") }

    def runs_per_day(schedule)
      cron = Fugit.parse(schedule)
      day = Time.utc(2026, 11, 1)
      times = []
      at = cron.next_time(day - 1).to_t.utc
      while at < day + 1.day
        times << at
        at = cron.next_time(at).to_t.utc
      end
      times
    end

    it "opens a Sync Window at 00, 06, 12 and 18 UTC" do
      window = tasks.fetch("achievement_sync_window")

      expect(window["class"]).to eq("Achievements::SyncWindowJob")
      expect(runs_per_day(window.fetch("schedule")).map(&:hour)).to eq([ 0, 6, 12, 18 ])
    end

    it "adds no entry more frequent than the existing every-minute one" do
      tasks.each_value do |task|
        expect(runs_per_day(task.fetch("schedule")).size).to be <= 24 * 60
      end
    end
  end

  describe "catch-up on boot" do
    let(:initializer) { Rails.root.join("config/initializers/achievement_sync_catch_up.rb") }

    before { allow(Rails.application.config).to receive(:after_initialize).and_yield }

    it "enqueues the three Provider ticks once in a server process" do
      stub_const("Rails::Server", Class.new)

      load initializer

      UserLinkedAccount::PROVIDERS.each do |provider|
        expect(Achievements::ProviderTickJob).to have_been_enqueued.with(provider).exactly(:once)
      end
    end

    it "enqueues nothing outside a server process (console, rake, specs)" do
      hide_const("Rails::Server")

      load initializer

      expect(Achievements::ProviderTickJob).not_to have_been_enqueued
    end
  end
end
