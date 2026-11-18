# frozen_string_literal: true

require "rails_helper"
require "fugit"

# The Birthday Post's schedule (ticket #401). Who it greets is covered through
# the API in spec/requests/api/v1/behavior/birthday_post_spec.rb.
RSpec.describe Birthdays::PostJob do
  it "runs every day at 10:00 New York time in production, through the change of clocks" do
    task = YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result)
      .fetch("production").values.find { |entry| entry["class"] == described_class.name }
    cron = Fugit.parse(task.fetch("schedule"))
    new_york = ActiveSupport::TimeZone["America/New_York"]

    runs = [ cron.next_time(Time.utc(2026, 10, 30)).to_t ]
    runs << cron.next_time(runs.last).to_t while runs.size < 4

    expect(runs.map { |run| run.in_time_zone(new_york).strftime("%F %R") })
      .to eq([ "2026-10-30 10:00", "2026-10-31 10:00", "2026-11-01 10:00", "2026-11-02 10:00" ])
  end
end
