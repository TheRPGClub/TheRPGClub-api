# frozen_string_literal: true

require "rails_helper"

RSpec.describe Voting::AdvanceRoundsJob do
  include ActiveSupport::Testing::TimeHelpers

  # Opens Friday 2026-10-30 noon ET; the 5-day reminder is due 2026-10-25 17:00
  # ET (21:00 UTC).
  let(:opens_at) { Time.utc(2026, 10, 30, 16) }
  let(:reminder_at) { Time.utc(2026, 10, 25, 21) }
  let!(:round) { create(:voting_round, voting_opens_at: opens_at) }

  before { Voting::SweepSchedule.clear }
  after { Voting::SweepSchedule.clear }

  def perform_at(time)
    travel_to(time) { described_class.perform_now }
  end

  it "does nothing, not even read the schedule, with automation off" do
    expect(Voting::SweepSchedule).not_to receive(:due?)

    perform_at(reminder_at)

    expect(VotingEvent.count).to eq(0)
  end

  context "with automation on" do
    before { allow(Voting).to receive(:automation_enabled?).and_return(true) }

    it "sweeps once, then skips the database until the round's next event is due" do
      perform_at(Time.utc(2026, 10, 20))
      expect(Voting::SweepSchedule.due?(Time.utc(2026, 10, 20, 0, 1))).to be(false)

      expect(Voting::AdvanceRounds).not_to receive(:call)
      expect(VotingRound).not_to receive(:current)
      perform_at(Time.utc(2026, 10, 20, 0, 1))
    end

    it "sweeps when the next event comes due and queues it" do
      perform_at(reminder_at - 1.minute)
      perform_at(reminder_at)

      expect(VotingEvent.pluck(:kind)).to eq(%w[nomination_reminder_5d])
      expect(Voting::SweepSchedule.due?(reminder_at + 1.minute)).to be(false)
    end

    it "looks again by RECHECK when nothing is scheduled" do
      round.update!(decided_at: Time.utc(2026, 10, 1))
      perform_at(Time.utc(2026, 10, 20))


      swept_at = Time.utc(2026, 10, 20)
      expect(Voting::SweepSchedule.due?(swept_at + 1.hour)).to be(false)
      expect(Voting::SweepSchedule.due?(swept_at + Voting::SweepSchedule::RECHECK)).to be(true)
    end

    it "sweeps on the next minute after a round changes" do
      perform_at(Time.utc(2026, 10, 20))

      round.update!(voting_opens_at: Time.utc(2026, 10, 23, 16))

      expect(Voting::SweepSchedule.due?(Time.utc(2026, 10, 20, 0, 1))).to be(true)
    end
  end
end
