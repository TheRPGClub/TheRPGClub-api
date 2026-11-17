# frozen_string_literal: true

require "rails_helper"

# A slot move refreshes the member's Runs (Challenges.refresh_runs!), which
# locks them in id order. The move must take its locks in that same order,
# or it deadlocks with a refresh running at the same time (a Game Completion
# the bot logs while the member moves a game).
RSpec.describe Challenges::Runs do
  self.use_transactional_tests = false

  let!(:member) { create(:user) }
  let!(:pool_challenge) { create(:challenge) }
  let!(:slots_challenge) do
    create(:challenge, challenge_format: "slots", pool_target: nil, slots_first_year: 1995, slots_last_year: 1999)
  end
  let!(:pool_run) { create(:challenge_run, challenge: pool_challenge, user: member) }
  let!(:slots_run) { create(:challenge_run, challenge: slots_challenge, user: member) }
  let!(:game) { create(:game) }

  before { ChallengeRunEntry.create!(run: slots_run, game: game, state: "cleared", slot_year: 1995) }

  after do
    runs = ChallengeRun.where(user_id: member.user_id)
    ChallengeRunEntry.where(run_id: runs.select(:id)).delete_all
    runs.delete_all
    challenges = Challenge.where(id: [ pool_challenge.id, slots_challenge.id ])
    game_ids = ChallengePoolGame.where(challenge_id: challenges.select(:id)).pluck(:game_id) + [ game.game_id ]
    ChallengePoolGame.where(challenge_id: challenges.select(:id)).delete_all
    challenges.delete_all
    GamedbGame.where(game_id: game_ids).delete_all
    RpgClubUser.where(user_id: [ member.user_id, pool_challenge.host_user_id, slots_challenge.host_user_id ])
      .delete_all
  end

  def in_thread(&block)
    Thread.new do
      Thread.current.report_on_exception = false
      ActiveRecord::Base.connection_pool.with_connection(&block)
    end
  end

  def wait_for_a_blocked_lock
    50.times do
      return if ActiveRecord::Base.connection.select_value("SELECT count(*) FROM pg_locks WHERE NOT granted").positive?

      sleep 0.05
    end
    raise "nothing waited on a lock"
  end

  it "moves a game while a refresh of the member's Runs is under way, without deadlocking" do
    refresh_holds_first_run = Queue.new
    move_waits = Queue.new
    # A refresh that has locked the member's first Run and goes on to the next.
    refresh = in_thread do
      ChallengeRun.transaction do
        ChallengeRun.where(id: pool_run.id).lock.to_a
        refresh_holds_first_run << true
        move_waits.pop
        ChallengeRun.where(id: slots_run.id).lock.to_a
      end
    end
    refresh_holds_first_run.pop

    move = in_thread { described_class.move!(ChallengeRun.find(slots_run.id), game_id: game.game_id, year: 1995) }
    wait_for_a_blocked_lock
    move_waits << true

    expect { [ refresh, move ].each(&:value) }.not_to raise_error
  end
end
