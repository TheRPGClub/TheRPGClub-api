# frozen_string_literal: true

require "rails_helper"

# Game of the Year nominations (spec api#471, ticket api#473): a member
# nominates up to three games released in the year, while the GOTY Vote is
# nominating. Playing the game is not required.
RSpec.describe Goty::Nominate do
  include ActiveSupport::Testing::TimeHelpers

  let(:member) { create(:user) }
  let(:nominating_at) { Time.utc(2027, 1, 5) }

  def game_from(year)
    create(:game, initial_release_date: Time.utc(year, 6, 1))
  end

  def nominate(game, user: member, reason: nil, at: nominating_at)
    travel_to(at) { described_class.call(year: 2026, user_id: user.user_id, gamedb_game_id: game.game_id, reason: reason) }
  end

  context "while nominating" do
    before { create(:goty_vote, year: 2026) }

    it "nominates a game released in the year, with a reason" do
      game = game_from(2026)

      result = nominate(game, reason: "It was great")

      expect(result).to be_created
      expect(result.nomination).to have_attributes(year: 2026, user_id: member.user_id,
        gamedb_game_id: game.game_id, reason: "It was great")
      expect(result.nomination.nominated_at).to be_present
    end

    it "updates the reason when the member nominates the same game again" do
      game = game_from(2026)
      nominate(game, reason: "First")

      result = nominate(game, reason: "Second")

      expect(result).not_to be_created
      expect(result.nomination.reason).to eq("Second")
      expect(GotyNomination.where(year: 2026, user_id: member.user_id).count).to eq(1)
    end

    it "refuses a fourth game but still lets the member re-nominate one of their three" do
      games = Array.new(3) { game_from(2026) }
      games.each { |game| nominate(game) }

      expect { nominate(game_from(2026)) }.to raise_error(described_class::CapReachedError, /3/)
      expect(nominate(games.first, reason: "Edited").nomination.reason).to eq("Edited")
    end

    it "counts the cap per member" do
      Array.new(3) { game_from(2026) }.each { |game| nominate(game) }

      expect(nominate(game_from(2026), user: create(:user))).to be_created
    end

    it "refuses a game released in another year with the reason" do
      expect { nominate(game_from(2025)) }.to raise_error(described_class::IneligibleError) { |error|
        expect(error.reason).to eq("not_released_in_year")
      }
    end

    it "refuses a game with no known release, asking staff to record one" do
      expect { nominate(create(:game)) }.to raise_error(described_class::IneligibleError) { |error|
        expect(error.reason).to eq("release_unknown")
        expect(error.message).to match(/ask staff to record its release/i)
      }
    end

    it "refuses a reason over 1500 characters" do
      expect { nominate(game_from(2026), reason: "x" * 1501) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  it "is closed before nominations open and once voting opens" do
    vote = create(:goty_vote, year: 2026)
    game = game_from(2026)

    expect { nominate(game, at: vote.nominations_open_at - 1.minute) }
      .to raise_error(described_class::NominationsClosedError, /not open/)
    expect { nominate(game, at: vote.voting_opens_at) }
      .to raise_error(described_class::NominationsClosedError)
  end

  it "raises not found for a year with no GOTY Vote" do
    expect { nominate(game_from(2026)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe "two nominations by one member at once" do
    self.use_transactional_tests = false

    let(:release) { Queue.new }
    let(:threads) { [] }

    after do
      release << true
      threads.each do |thread|
        thread.join(5)
      rescue StandardError
        nil # the refused nomination's error, already checked
      end
      GotyNomination.where(user_id: member.user_id).delete_all
      GotyVote.where(year: 2026).delete_all
      GamedbGame.where(game_id: @game_ids).delete_all
      member.destroy!
    end

    it "can't get past three" do
      create(:goty_vote, year: 2026)
      games = Array.new(4) { game_from(2026) }
      @game_ids = games.map(&:game_id)
      games.first(2).each { |game| nominate(game) }

      travel_to(nominating_at) do
        # The third nomination is held open in its transaction while the
        # fourth is posted.
        threads << in_thread do
          GotyNomination.transaction do
            described_class.call(year: 2026, user_id: member.user_id, gamedb_game_id: games[2].game_id, reason: nil)
            release.pop
          end
        end
        wait_until { lock_held? }
        threads << in_thread do
          described_class.call(year: 2026, user_id: member.user_id, gamedb_game_id: games[3].game_id, reason: nil)
        end
        wait_for_a_blocked_lock
        release << true

        expect { threads[0].value }.not_to raise_error
        expect { threads[1].value }.to raise_error(described_class::CapReachedError)
      end
      expect(GotyNomination.where(year: 2026, user_id: member.user_id).count).to eq(3)
    end

    def lock_held?
      GotyNomination.connection.select_value("SELECT count(*) FROM pg_locks WHERE locktype = 'advisory'").positive?
    end

    def wait_until(timeout: 2.5)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      until yield
        raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.05
      end
    end
  end
end
