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

    it "queues a GOTY kind once per GOTY Vote, alongside a round's events" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)
      create(:goty_vote, year: 2026)
      event(kind: "voting_opened")

      2.times { described_class.emit!(goty_year: 2026, kind: "goty_voting_opened", payload: { a: 1 }) }

      expect(described_class.where(goty_year: 2026).pluck(:kind, :round_number)).to eq([ [ "goty_voting_opened", nil ] ])
      expect(described_class.where(round_number: round_number).count).to eq(1)
    end
  end

  describe "validation" do
    before { create(:goty_vote, year: 2026) }

    it "belongs to a round or a GOTY Vote, not both or neither" do
      expect(described_class.new(kind: "voting_opened", available_at: now)).not_to be_valid
      expect(described_class.new(round_number: 1, goty_year: 2026, kind: "goty_decided", available_at: now))
        .not_to be_valid
    end

    it "keeps GOTY kinds on a GOTY Vote and round kinds on a round" do
      expect(described_class.new(goty_year: 2026, kind: "voting_opened", available_at: now)).not_to be_valid
      expect(described_class.new(round_number: 1, kind: "goty_decided", available_at: now)).not_to be_valid
      expect(described_class.new(goty_year: 2026, kind: "goty_decided", available_at: now)).to be_valid
    end

    it "is enforced by the database too" do
      expect do
        described_class.insert_all!([ { kind: "voting_opened", available_at: now, payload: {} } ])
      end.to raise_error(ActiveRecord::StatementInvalid, /ck_voting_events_round_or_goty_year/)
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

  describe ".next_poll_at" do
    it "is nil when nothing is pending or scheduled" do
      event(delivered_at: now - 1.minute)
      event(kind: "nomination_reminder_5d", expires_at: now - 1.second)

      expect(described_class.next_poll_at(now)).to be_nil
    end

    it "is now while an event is claimable" do
      event

      expect(described_class.next_poll_at(now)).to eq(now)
    end

    it "is when the earliest pending event falls due or its lease runs out" do
      event(available_at: now + 2.hours)
      event(kind: "voting_closed", claimed_until: now + 3.minutes)

      expect(described_class.next_poll_at(now)).to eq(now + 3.minutes)
    end

    it "allows the sweep time to queue the round's next event" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)
      round = create(:voting_round, voting_opens_at: now + 10.days)

      expect(described_class.next_poll_at(now))
        .to eq(Voting::Schedule.reminder_at(round.voting_opens_at, 5) + VotingEvent::SWEEP_LAG)
    end

    it "allows the sweep time to queue the GOTY Vote's next event when it comes first" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)
      create(:voting_round, voting_opens_at: Time.utc(2027, 1, 29, 17))
      vote = create(:goty_vote, year: 2026)
      at = Time.utc(2026, 12, 20)

      expect(described_class.next_poll_at(at)).to eq(vote.nominations_open_at + VotingEvent::SWEEP_LAG)
    end

    it "leaves out the GOTY Vote's sweep while its Feature is Off, as the sweep does" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)
      set_feature_flag("goty_vote", "off")
      december = Time.utc(2026, 12, 2)
      round = create(:voting_round, voting_opens_at: december + 10.days)

      # December with no GOTY Vote yet: its creation would be due now.
      expect(described_class.next_poll_at(december))
        .to eq(Voting::Schedule.reminder_at(round.voting_opens_at, 5) + VotingEvent::SWEEP_LAG)
    end

    it "leaves out the round's sweep while Voting & GOTM is Off" do
      allow(Voting).to receive(:automation_enabled?).and_return(true)
      set_feature_flag("voting_gotm", "off")
      set_feature_flag("goty_vote", "off")
      create(:voting_round, voting_opens_at: now + 10.days)

      expect(described_class.next_poll_at(now)).to be_nil
    end
  end
end
