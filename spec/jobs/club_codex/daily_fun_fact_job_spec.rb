# frozen_string_literal: true

require "rails_helper"
require "fugit"

# The Daily Fun Fact (spec #397, ticket #406): at 15:00 New York time the job
# draws the next Fun Fact from the queue /funfact uses and asks the bot to
# post it, once per club day.
RSpec.describe ClubCodex::DailyFunFactJob do
  include ActiveSupport::Testing::TimeHelpers

  # 15:00 in New York on 18 November 2026 (EST, UTC-5).
  let(:run_at) { Time.utc(2026, 11, 18, 20) }
  let(:regular) { create(:user, role_member: true, role_regular: true) }

  before { set_feature_flag("club_codex", "live") }

  def perform_at(time)
    travel_to(time) { described_class.perform_now }
  end

  def add_fun_fact(body, created_at: Time.current)
    create(:codex_entry, :fun_fact, author: regular, body: body, created_at: created_at)
  end

  def daily_fun_facts = BotJob.where(kind: "daily_fun_fact").order(:id)

  it "runs every day at 15:00 New York time in production, through the change of clocks" do
    task = YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result)
      .fetch("production").values.find { |entry| entry["class"] == described_class.name }
    cron = Fugit.parse(task.fetch("schedule"))
    new_york = ActiveSupport::TimeZone["America/New_York"]

    runs = [ cron.next_time(Time.utc(2026, 10, 30)).to_t ]
    runs << cron.next_time(runs.last).to_t while runs.size < 4

    expect(runs.map { |run| run.in_time_zone(new_york).strftime("%F %R") })
      .to eq([ "2026-10-30 15:00", "2026-10-31 15:00", "2026-11-01 15:00", "2026-11-02 15:00" ])
  end

  it "enqueues one daily_fun_fact bot job for the club date, carrying the next Fun Fact" do
    add_fun_fact("Older.", created_at: 2.days.ago)
    newest = add_fun_fact("Newest.", created_at: 1.day.ago)

    perform_at(run_at)

    expect(daily_fun_facts.map(&:payload))
      .to eq([ { "club_date" => "2026-11-18", "entry_id" => newest.id, "feature_key" => "club_codex" } ])
  end

  it "enqueues nothing on a second run the same club day, and leaves the queue where it was" do
    add_fun_fact("First.", created_at: 2.days.ago)
    add_fun_fact("Second.", created_at: 1.day.ago)
    perform_at(run_at)

    expect { perform_at(run_at + 8.hours) }.not_to change(daily_fun_facts, :count)
    expect(ClubCodex::FunFactQueue.ordered.map(&:body)).to eq(%w[First. Second.])
  end

  it "enqueues the next Fun Fact on the next club day" do
    add_fun_fact("First.", created_at: 2.days.ago)
    second = add_fun_fact("Second.", created_at: 1.day.ago)
    first = CodexEntry.find_by!(body: "First.")

    perform_at(run_at)
    perform_at(run_at + 1.day)

    expect(daily_fun_facts.map { |job| job.payload.values_at("club_date", "entry_id") })
      .to eq([ [ "2026-11-18", second.id ], [ "2026-11-19", first.id ] ])
  end

  it "enqueues nothing with no Fun Facts" do
    create(:codex_entry, :lore_entry, author: regular)

    perform_at(run_at)

    expect(daily_fun_facts).to be_empty
  end

  it "posts that day's Fun Fact once there is one, after a run that found none" do
    perform_at(run_at)
    added = travel_to(run_at + 1.hour) { add_fun_fact("Late.") }

    perform_at(run_at + 2.hours)

    expect(daily_fun_facts.map { |job| job.payload["entry_id"] }).to eq([ added.id ])
  end

  it "enqueues nothing and doesn't move the queue when the Club Codex is Off" do
    fact = add_fun_fact("Waiting.")
    set_feature_flag("club_codex", "off")

    perform_at(run_at)

    expect(daily_fun_facts).to be_empty
    expect(fact.reload.last_shown_at).to be_nil
  end

  it "still posts in Preview, for the bot to route to the staff test channel" do
    add_fun_fact("Preview.")
    set_feature_flag("club_codex", "preview")

    perform_at(run_at)

    expect(daily_fun_facts.map { |job| job.payload["feature_key"] }).to eq([ "club_codex" ])
  end

  describe "and /funfact", type: :request do
    it "advances the same queue: the fact it posts isn't drawn next by POST /fun_facts/draw" do
      add_fun_fact("Older.", created_at: 2.days.ago)
      newest = add_fun_fact("Newest.", created_at: 1.day.ago)
      perform_at(run_at)

      travel_to(run_at + 1.minute) do
        post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(regular), as: :json
      end

      expect(daily_fun_facts.first.payload["entry_id"]).to eq(newest.id)
      expect(json.dig("fun_fact", "body")).to eq("Older.")
    end

    it "posts the next fact even after /funfact drew one that day" do
      add_fun_fact("Older.", created_at: 2.days.ago)
      add_fun_fact("Newest.", created_at: 1.day.ago)

      travel_to(run_at - 1.hour) do
        post "/api/v1/codex/fun_facts/draw", headers: auth_headers_for(regular), as: :json
      end
      perform_at(run_at)

      expect(json.dig("fun_fact", "body")).to eq("Newest.")
      expect(daily_fun_facts.map { |job| CodexEntry.find(job.payload["entry_id"]).body }).to eq([ "Older." ])
    end
  end

  it "rolls the draw back when the bot job can't be queued" do
    fact = add_fun_fact("Kept.")
    allow(BotJob).to receive(:enqueue!).and_raise(ActiveRecord::RecordInvalid)

    expect { perform_at(run_at) }.to raise_error(ActiveRecord::RecordInvalid)

    expect(fact.reload.last_shown_at).to be_nil
    expect(DailyFunFactPost.count).to eq(0)
  end

  it "keeps the day posted when its Fun Fact is deleted, so a re-run posts nothing" do
    fact = add_fun_fact("Deleted later.")
    add_fun_fact("Never today.", created_at: 1.day.ago)
    perform_at(run_at)

    fact.destroy!

    expect { perform_at(run_at + 1.hour) }.not_to change(daily_fun_facts, :count)
  end
end
