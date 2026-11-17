# frozen_string_literal: true

require "rails_helper"

# A Challenge's rules lock once it has a Run (Challenges::Form). A rule edit
# and the first Run starting at the same moment must not both succeed: one
# waits for the other, so either the Run starts under the new rules or the
# edit is refused as locked.
RSpec.describe "Challenge rules lock against a first Run" do
  include ActiveSupport::Testing::TimeHelpers

  self.use_transactional_tests = false

  let!(:member) { create(:user) }
  let!(:challenge) { create(:challenge) }
  let(:closed_season) { { season_start_month: 6, season_start_day: 21, season_end_month: 9, season_end_day: 22 } }

  # Mid-October 2026 in the club's time zone.
  around { |example| travel_to(Time.zone.parse("2026-10-15 12:00:00 -04:00")) { example.run } }

  after do
    ChallengeRun.where(challenge_id: challenge.id).delete_all
    game_ids = ChallengePoolGame.where(challenge_id: challenge.id).pluck(:game_id)
    ChallengePoolGame.where(challenge_id: challenge.id).delete_all
    Challenge.where(id: challenge.id).delete_all
    GamedbGame.where(game_id: game_ids).delete_all
    RpgClubUser.where(user_id: [ member.user_id, challenge.host_user_id ]).delete_all
  end

  it "starts the Run only after a rule edit under way, under the edited rules" do
    edit_holds_challenge = Queue.new
    start_waits = Queue.new
    # An edit that has locked the Challenge and makes it Seasonal, Closed today.
    edit = in_thread do
      Challenge.transaction do
        Challenge.lock.find(challenge.id)
        edit_holds_challenge << true
        start_waits.pop
        Challenge.where(id: challenge.id).update_all(schedule: "seasonal", **closed_season)
      end
    end
    edit_holds_challenge.pop

    start = in_thread { Challenges::Runs.start!(Challenge.find(challenge.id), member.user_id) }
    begin
      wait_for_a_blocked_lock
    ensure
      start_waits << true
    end

    edit.value
    expect { start.value }.to raise_error(Challenges::RunRefused) { |error| expect(error.code).to eq("challenge_closed") }
    expect(ChallengeRun.where(challenge_id: challenge.id)).to be_empty
  end

  it "refuses a rule edit made while the first Run starts" do
    run_holds_challenge = Queue.new
    edit_waits = Queue.new
    # A first Run starting: it has locked the Challenge and inserted the Run.
    first_run = in_thread do
      Challenge.transaction do
        Challenge.lock.find(challenge.id)
        ChallengeRun.create!(challenge_id: challenge.id, user_id: member.user_id)
        run_holds_challenge << true
        edit_waits.pop
      end
    end
    run_holds_challenge.pop

    edit = in_thread do
      Challenges::Form.new(Challenge.find(challenge.id),
        "schedule" => "seasonal", "season" => { "start" => "06-21", "end" => "09-22" }).save!
    end
    begin
      wait_for_a_blocked_lock
    ensure
      edit_waits << true
    end

    first_run.value
    expect { edit.value }.to raise_error(Challenges::RulesLocked)
    expect(Challenge.find(challenge.id).schedule).to eq("always_open")
  end
end
