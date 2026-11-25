# frozen_string_literal: true

module Goty
  # Nominates (or re-nominates) a game for a year's Game of the Year on a
  # member's behalf (spec api#471, ticket api#473).
  #
  # Rules:
  # - Open only while the GOTY Vote is nominating (NominationsClosedError).
  # - The game must be eligible for the year (Goty::Eligibility); otherwise
  #   IneligibleError carries the reason. Playing it is not required.
  # - A member nominates each game once a year: nominating it again only
  #   updates the reason.
  # - At most CAP games per member per year (CapReachedError).
  #
  # Concurrency: nominations by one member for one year are serialized with a
  # transaction-scoped advisory lock, as in Voting::CastVote, since row locks
  # cannot stop two concurrent INSERTs from passing the cap together. The
  # unique (year, user, game) index backs up the once-per-game rule.
  class Nominate
    class NominationsClosedError < StandardError; end
    class CapReachedError < StandardError; end

    class IneligibleError < StandardError
      attr_reader :reason

      def initialize(reason, message)
        @reason = reason
        super(message)
      end
    end

    CAP = 3

    Result = Data.define(:nomination, :created) do
      def created? = created
    end

    def self.call(...) = new.call(...)

    def call(year:, user_id:, gamedb_game_id:, reason:)
      vote = GotyVote.find(year)
      raise NominationsClosedError, closed_message(vote) unless vote.nominations_open?

      game = GamedbGame.find(gamedb_game_id)
      check_eligible!(game, vote.year)

      GotyNomination.transaction do
        acquire_lock!(vote.year, user_id)
        nomination = GotyNomination.find_or_initialize_by(year: vote.year, user_id: user_id.to_s,
          gamedb_game_id: game.game_id)
        created = nomination.new_record?
        check_cap!(vote.year, user_id) if created
        nomination.goty_vote = vote
        nomination.reason = reason.presence
        nomination.save!
        Result.new(nomination: nomination.reload, created: created)
      end
    end

    private

    def closed_message(vote)
      if Time.current < vote.nominations_open_at
        "Game of the Year nominations for #{vote.year} are not open yet " \
          "(they open at #{vote.nominations_open_at.iso8601})"
      else
        "Game of the Year nominations for #{vote.year} are not open: they closed when voting opened " \
          "at #{vote.voting_opens_at.iso8601}"
      end
    end

    def check_eligible!(game, year)
      reason = Goty::Eligibility.check(game, year).reason
      return if reason.nil?

      message =
        if reason == "release_unknown"
          "#{game.title} has no known release date, so it can't be nominated yet: ask staff to record its release"
        else
          "#{game.title} was not first released in #{year}, so it can't be nominated for Game of the Year #{year}"
        end
      raise IneligibleError.new(reason, message)
    end

    def check_cap!(year, user_id)
      count = GotyNomination.where(year: year, user_id: user_id.to_s).count
      return if count < CAP

      raise CapReachedError,
        "you already have #{CAP} Game of the Year nominations for #{year}: withdraw one to nominate another"
    end

    # Held until commit or rollback; only blocks another nomination by the
    # same member for the same year.
    def acquire_lock!(year, user_id)
      sql = GotyNomination.sanitize_sql([
        "SELECT pg_advisory_xact_lock(hashtext(?), hashtext(?))", "goty_nominations:#{user_id}", year.to_s
      ])
      GotyNomination.connection.execute(sql)
    end
  end
end
