# frozen_string_literal: true

require "rails_helper"

RSpec.describe Goty::AdvanceVotes do
  # GOTY Vote 2026's default calendar: nominations open 2027-01-01 00:00 ET
  # (05:00 UTC); the reminders go out at 17:00 ET on 2027-01-10 and
  # 2027-01-14; voting opens Friday 2027-01-15 noon ET (17:00 UTC) and closes
  # at the end of Sunday 2027-01-17 ET.
  let(:nominations_open) { Time.utc(2027, 1, 1, 5) }
  let(:reminder_5d) { Time.utc(2027, 1, 10, 22) }
  let(:reminder_1d) { Time.utc(2027, 1, 14, 22) }
  let(:voting_open) { Time.utc(2027, 1, 15, 17) }
  let(:voting_closed) { Time.utc(2027, 1, 18, 5) }

  def kinds
    VotingEvent.where(goty_year: 2026).order(:id).pluck(:kind)
  end

  def payload(kind)
    VotingEvent.find_by!(goty_year: 2026, kind: kind).payload
  end

  def sweep(at, times: 2)
    times.times { described_class.call(now: at) }
  end

  def vote_for(award, game, runoff: false)
    GotyBallotVote.create!(year: 2026, award: award, user_id: create(:user).user_id,
      gamedb_game_id: game.game_id, runoff: runoff)
  end

  def award(data, key)
    data.fetch("awards").find { |row| row["award"] == key }
  end

  it "does nothing with automation off" do
    described_class.call(now: voting_closed)

    expect(GotyVote.count).to eq(0)
    expect(VotingEvent.count).to eq(0)
  end

  context "with automation on" do
    before { allow(Voting).to receive(:automation_enabled?).and_return(true) }

    let(:gotm_a) { create(:game, title: "Gotm A") }
    let(:gotm_b) { create(:game, title: "Gotm B") }
    let(:nr_only) { create(:game, title: "Nr Only") }
    let(:new_x) { create(:game, title: "New X", initial_release_date: Date.new(2026, 3, 1)) }
    let(:new_y) { create(:game, title: "New Y", initial_release_date: Date.new(2026, 8, 1)) }

    before do
      create(:gotm_entry, round_number: 900_001, month_year: "March 2026", game: gotm_a)
      create(:gotm_entry, round_number: 900_002, month_year: "April 2026", game: gotm_b)
      create(:nr_gotm_entry, round_number: 900_001, month_year: "March 2026", game: nr_only)
    end

    it "runs a year end to end, queuing each post once" do
      sweep(Time.utc(2026, 1, 1, 4))
      expect(GotyVote.exists?(2026)).to be(false)

      sweep(Time.utc(2026, 1, 1, 5))
      vote = GotyVote.find(2026)
      expect(vote.phase(Time.utc(2026, 1, 1, 5))).to eq("upcoming")
      expect(kinds).to be_empty

      sweep(nominations_open)
      expect(kinds).to eq(%w[goty_nominations_opened])
      expect(payload("goty_nominations_opened")).to include(
        "kind" => "goty_nominations_opened", "year" => 2026, "name" => "GOTY Vote 2026", "nomination_cap" => 3,
        "voting_opens_at" => voting_open.as_json
      )
      expect(award(payload("goty_nominations_opened"), "gotm")["games"].pluck("title")).to eq([ "Gotm A", "Gotm B" ])
      expect(VotingEvent.find_by(goty_year: 2026, kind: "goty_nominations_opened").expires_at).to eq(voting_open)

      [ new_x, new_x, new_y ].each { |game| create(:goty_nomination, year: 2026, game: game) }

      sweep(reminder_5d)
      sweep(reminder_1d)
      expect(kinds).to eq(%w[goty_nominations_opened goty_nomination_reminder_5d goty_nomination_reminder_1d])
      expect(payload("goty_nomination_reminder_1d")).to include("days_before" => 1)
      expect(award(payload("goty_nomination_reminder_1d"), "game_of_the_year")["games"].pluck("title"))
        .to eq([ "New X", "New Y" ])
      expect(VotingEvent.find_by(goty_year: 2026, kind: "goty_nomination_reminder_1d").expires_at).to eq(voting_open)

      sweep(voting_open)
      expect(vote.reload.candidates_frozen_at).to eq(voting_open)
      expect(kinds.last).to eq("goty_voting_opened")
      opened = payload("goty_voting_opened")
      expect(award(opened, "gotm")).to include("cap" => 1, "uncontested" => false)
      expect(award(opened, "gotm")["games"].first)
        .to include("gamedb_game_id" => gotm_a.game_id, "title" => "Gotm A", "votes" => nil, "runoff_votes" => nil)
      expect(award(opened, "nr_gotm")).to include("uncontested" => true)
      expect(VotingEvent.find_by(goty_year: 2026, kind: "goty_voting_opened").expires_at).to eq(vote.voting_closes_at)

      vote_for("gotm", gotm_a)
      vote_for("gotm", gotm_b)
      2.times { vote_for("game_of_the_year", new_x) }
      vote_for("game_of_the_year", new_y)

      sweep(voting_closed)
      expect(kinds.last).to eq("goty_runoff_opened")
      runoff = payload("goty_runoff_opened")
      expect(runoff).to include("runoff_closes_at" => (voting_closed + 24.hours).as_json)
      expect(award(runoff, "gotm")).to include("runoff_ballot" => [ gotm_a.game_id, gotm_b.game_id ], "winner" => nil)
      expect(award(runoff, "gotm")["games"].pluck("votes")).to eq([ 1, 1 ])
      expect(award(runoff, "game_of_the_year")["winner"])
        .to include("gamedb_game_id" => new_x.game_id, "decided_by" => "vote")
      expect(award(runoff, "nr_gotm")["winner"]).to include("gamedb_game_id" => nr_only.game_id,
        "decided_by" => "uncontested")
      expect(VotingEvent.find_by(goty_year: 2026, kind: "goty_runoff_opened").expires_at).to eq(voting_closed + 24.hours)

      vote_for("gotm", gotm_b, runoff: true)
      sweep(voting_closed + 24.hours)
      sweep(voting_closed + 48.hours)

      expect(kinds).to eq(%w[
        goty_nominations_opened goty_nomination_reminder_5d goty_nomination_reminder_1d goty_voting_opened
        goty_runoff_opened goty_runoff_closed goty_decided
      ])
      expect(vote.reload.phase(voting_closed + 48.hours)).to eq("decided")
      decided = payload("goty_decided")
      expect(award(decided, "gotm")["winner"]).to include("gamedb_game_id" => gotm_b.game_id, "decided_by" => "runoff")
      expect(award(decided, "gotm")["games"].map { |game| game.values_at("votes", "runoff_votes") })
        .to eq([ [ 1, 0 ], [ 1, 1 ] ])
      expect(award(decided, "game_of_the_year")["games"].pluck("votes")).to eq([ 2, 1 ])
      expect(award(payload("goty_runoff_closed"), "gotm")["winner"]).to include("decided_by" => "runoff")
    end

    it "decides at once with no tie" do
      create(:goty_vote, year: 2026)
      sweep(voting_open)
      vote_for("gotm", gotm_a)
      sweep(voting_closed)

      expect(kinds).to eq(%w[goty_voting_opened goty_decided])
      expect(award(payload("goty_decided"), "gotm")["winner"]).to include("gamedb_game_id" => gotm_a.game_id)
      expect(award(payload("goty_decided"), "game_of_the_year")).to include("games" => [], "winner" => nil)
    end

    it "posts no stale nomination posts when the first sweep comes after voting opened" do
      create(:goty_vote, year: 2026)

      sweep(voting_open + 1.hour)

      expect(kinds).to eq(%w[goty_voting_opened])
    end

    it "posts neither the vote panels nor anything before when the first sweep comes after the close" do
      create(:goty_vote, year: 2026)

      sweep(voting_closed)

      expect(kinds).to eq(%w[goty_decided])
      expect(GotyVote.find(2026).candidates_frozen_at).to be_present
    end

    it "still queues the vote panels when a cast froze the candidates first" do
      vote = create(:goty_vote, year: 2026)
      Goty::FreezeCandidates.call(vote, now: voting_open)

      sweep(voting_open + 1.minute)

      expect(kinds).to eq(%w[goty_voting_opened])
    end

    it "queues a tie prompt when the runoff ties again, and the decision once an admin picks" do
      vote = create(:goty_vote, year: 2026)
      sweep(voting_open)
      vote_for("gotm", gotm_a)
      vote_for("gotm", gotm_b)
      sweep(voting_closed)
      vote_for("gotm", gotm_a, runoff: true)
      vote_for("gotm", gotm_b, runoff: true)

      sweep(voting_closed + 24.hours)

      expect(kinds).to eq(%w[goty_voting_opened goty_runoff_opened goty_runoff_closed goty_tie_pending])
      expect(award(payload("goty_tie_pending"), "gotm"))
        .to include("pending_tie" => [ gotm_a.game_id, gotm_b.game_id ], "winner" => nil)
      expect(vote.reload.phase(voting_closed + 25.hours)).to eq("tie")
    end

    it "catches up the current year's GOTY Vote on the first sweep, queuing no post" do
      sweep(Time.utc(2026, 11, 25))

      expect(GotyVote.pluck(:year)).to eq([ 2026 ])
      expect(VotingEvent.count).to eq(0)
    end

    it "creates the new year's GOTY Vote on 1 January (ET) while last year's takes nominations" do
      create(:goty_vote, year: 2026)

      sweep(Time.utc(2027, 1, 1, 4, 59))
      expect(GotyVote.pluck(:year)).to eq([ 2026 ])

      sweep(nominations_open)
      expect(GotyVote.order(:year).pluck(:year)).to eq([ 2026, 2027 ])
      expect(VotingEvent.where(goty_year: 2027)).to be_empty
      expect(kinds).to eq(%w[goty_nominations_opened])
    end

    it "creates last year's missing GOTY Vote in January, but never once its vote is due" do
      sweep(Time.utc(2027, 1, 3))
      expect(GotyVote.order(:year).pluck(:year)).to eq([ 2026, 2027 ])
      expect(kinds).to eq(%w[goty_nominations_opened])

      GotyVote.where(year: 2026).delete_all
      sweep(voting_open)
      expect(GotyVote.pluck(:year)).to eq([ 2027 ])
    end

    it "leaves round events alone" do
      round = create(:voting_round, voting_opens_at: Time.utc(2027, 1, 29, 17))
      VotingEvent.create!(round_number: round.round_number, kind: "voting_opened", available_at: voting_open)
      create(:goty_vote, year: 2026)

      sweep(voting_open)

      expect(VotingEvent.where(round_number: round.round_number).pluck(:kind)).to eq(%w[voting_opened])
      expect(kinds).to eq(%w[goty_voting_opened])
    end
  end

  describe ".next_event_at" do
    it "is nil with automation off" do
      expect(described_class.next_event_at(now: Time.utc(2026, 11, 20))).to be_nil
    end

    context "with automation on" do
      before { allow(Voting).to receive(:automation_enabled?).and_return(true) }

      it "is now while the year's GOTY Vote is missing" do
        now = Time.utc(2026, 11, 20)
        expect(described_class.next_event_at(now: now)).to eq(now)
      end

      it "points at 1 January (ET) of next year once this year's GOTY Vote exists" do
        create(:goty_vote, year: 2026, nominations_open_at: Time.utc(2027, 2, 1, 5),
          voting_opens_at: Time.utc(2027, 2, 12, 17))

        expect(described_class.next_event_at(now: Time.utc(2026, 11, 20))).to eq(Time.utc(2027, 1, 1, 5))
      end

      it "walks the calendar, skipping posts already queued or past their window" do
        create(:goty_vote, year: 2026)

        expect(described_class.next_event_at(now: Time.utc(2026, 12, 2))).to eq(nominations_open)
        described_class.call(now: nominations_open)
        expect(described_class.next_event_at(now: nominations_open)).to eq(reminder_5d)
        expect(described_class.next_event_at(now: reminder_5d + 1.hour)).to eq(reminder_5d + 1.hour)
        described_class.call(now: reminder_1d)
        expect(described_class.next_event_at(now: reminder_1d)).to eq(voting_open)
      end

      it "skips a reminder that falls before nominations open, instead of reporting it due" do
        late_open = Time.utc(2027, 1, 12, 5)
        create(:goty_vote, year: 2026, nominations_open_at: late_open)
        create(:goty_vote, year: 2027)

        expect(described_class.next_event_at(now: Time.utc(2027, 1, 11))).to eq(late_open)
        described_class.call(now: late_open)
        expect(kinds).to eq(%w[goty_nominations_opened])
        expect(described_class.next_event_at(now: late_open)).to eq(reminder_1d)
        described_class.call(now: reminder_1d)
        expect(kinds).to eq(%w[goty_nominations_opened goty_nomination_reminder_1d])
      end

      it "waits for the close once voting is open and queued" do
        create(:goty_vote, year: 2026)
        described_class.call(now: voting_open)

        expect(described_class.next_event_at(now: voting_open + 1.minute)).to eq(GotyVote.find(2026).voting_closes_at)
      end

      it "points at next 1 January once the year is decided and this year's exists" do
        create(:goty_vote, year: 2026, decided_at: Time.utc(2027, 1, 18))
        create(:goty_vote, year: 2027)

        expect(described_class.next_event_at(now: Time.utc(2027, 2, 1))).to eq(Time.utc(2028, 1, 1, 5))
      end
    end
  end
end
