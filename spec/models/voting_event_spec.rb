# frozen_string_literal: true

require "rails_helper"

RSpec.describe VotingEvent do
  let(:now) { Time.utc(2026, 10, 30, 16) }
  let(:round_number) { SecureRandom.random_number(1_000_000_000) }

  def event(**attrs)
    described_class.create!({ round_number: round_number, kind: "voting_opened", available_at: now - 1.minute }
      .merge(attrs))
  end

  describe ".emit!" do
    it "is a no-op while automation is off" do
      expect(described_class.emit!(round_number: round_number, kind: "voting_opened")).to be_nil
      expect(described_class.count).to eq(0)
    end

    it "queues a kind once per round" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)

      2.times { described_class.emit!(round_number: round_number, kind: "voting_opened", payload: { a: 1 }) }

      expect(described_class.where(round_number: round_number).count).to eq(1)
    end
  end

  describe ".claim!" do
    it "leases due events oldest first and skips leased, future, expired and delivered ones" do
      due = event(available_at: now - 2.minutes)
      later_due = event(kind: "voting_closed", available_at: now - 1.minute)
      event(kind: "round_decided", available_at: now + 1.minute)
      event(kind: "nomination_reminder_5d", expires_at: now - 1.second)
      event(kind: "nomination_reminder_1d", delivered_at: now - 1.minute)
      event(kind: "tie_pending", claimed_until: now + 1.minute)

      claimed = described_class.claim!(limit: 10, now: now)

      expect(claimed).to eq([ due, later_due ])
      expect(due.reload).to have_attributes(claimed_until: now + VotingEvent::LEASE, attempts: 1)
    end

    it "hands an unacked event out again once its lease runs out" do
      pending_event = event

      described_class.claim!(limit: 10, now: now)
      expect(described_class.claim!(limit: 10, now: now + 1.minute)).to be_empty
      expect(described_class.claim!(limit: 10, now: now + VotingEvent::LEASE)).to eq([ pending_event ])
      expect(pending_event.reload.attempts).to eq(2)
    end

    it "honors the limit" do
      event
      event(kind: "voting_closed")

      expect(described_class.claim!(limit: 1, now: now).size).to eq(1)
    end
  end

  describe "#acknowledge!" do
    it "marks the event delivered once" do
      pending_event = event
      pending_event.acknowledge!(now)
      pending_event.acknowledge!(now + 1.hour)

      expect(pending_event.reload.delivered_at).to eq(now)
      expect(described_class.claim!(limit: 10, now: now + 1.day)).to be_empty
    end
  end
end
