# frozen_string_literal: true

module Challenges
  # Challenge Activity (spec api#421, ticket api#424): recent Challenge
  # happenings club-wide, derived from what Runs, their entries and Editions
  # already store (there is no events table). Hidden Challenges are left
  # out for everyone; a deleted Challenge or Run takes its events with it.
  #
  #   run_started       a Run's `started_at` (an Assignment Run's: the draw)
  #   game_cleared      a Run entry's `cleared_on`, with its game
  #   run_finished      a Finished Run's `ended_at`
  #   signups_opened    an Edition's `signup_opens_on`
  #   edition_revealed  a revealed Edition's `reveal_on`
  #
  # Events carry the club date they happened on (`occurred_on`) and, where
  # the time is stored, the moment (`occurred_at`). Newest first: by date,
  # then by time, where an event known only by its date sorts as the start
  # of its club day.
  module Activity
    KINDS = %w[run_started game_cleared run_finished signups_opened edition_revealed].freeze

    Event = Data.define(:kind, :occurred_on, :occurred_at, :challenge, :user, :game, :run, :edition) do
      def sort_key = [ occurred_on, occurred_at || occurred_on.in_time_zone(ClubDay::TIME_ZONE) ]

      def as_json(*)
        { kind: kind, occurred_on: occurred_on.iso8601, occurred_at: occurred_at,
          challenge: { id: challenge.id, name: challenge.name, challenge_format: challenge.challenge_format,
                       tint: challenge.tint.as_json },
          user: user && Challenges.member(user),
          game: game && GameSummaryResource.new(game).serializable_hash,
          run_id: run&.id, edition: edition && { id: edition.id, year: edition.year } }
      end
    end

    # The `per` newest events. Each source reads its own `per` newest, and
    # the merged list keeps the `per` newest of those.
    def self.recent(per)
      challenges = Challenge.visible
      events = run_started(challenges, per) + game_cleared(challenges, per) + run_finished(challenges, per) +
        signups_opened(challenges, per) + edition_revealed(challenges, per)
      events.sort_by(&:sort_key).reverse.first(per)
    end

    def self.runs(challenges)
      ChallengeRun.where(challenge_id: challenges.select(:id)).preload(:challenge, :user, :edition)
    end

    def self.run_event(kind, run, at, game: nil, on: Challenges.today(at))
      Event.new(kind: kind, occurred_on: on, occurred_at: at, challenge: run.challenge, user: run.user, game: game,
        run: run, edition: run.edition)
    end

    def self.run_started(challenges, per)
      runs(challenges).order(started_at: :desc, id: :desc).limit(per)
        .map { |run| run_event("run_started", run, run.started_at) }
    end

    def self.run_finished(challenges, per)
      runs(challenges).where(status: "finished").where.not(ended_at: nil).order(ended_at: :desc, id: :desc)
        .limit(per).map { |run| run_event("run_finished", run, run.ended_at) }
    end

    # A Cleared game is dated by its Game Completion, so has no time.
    def self.game_cleared(challenges, per)
      ChallengeRunEntry.where(state: "cleared").where.not(cleared_on: nil)
        .where(run_id: ChallengeRun.where(challenge_id: challenges.select(:id)).select(:id))
        .order(cleared_on: :desc, id: :desc).limit(per)
        .preload(game: :images, run: %i[challenge user edition])
        .map { |entry| run_event("game_cleared", entry.run, nil, game: entry.game, on: entry.cleared_on) }
    end

    def self.editions(challenges) = ChallengeEdition.where(challenge_id: challenges.select(:id)).preload(:challenge)

    def self.edition_event(kind, edition, on)
      Event.new(kind: kind, occurred_on: on, occurred_at: nil, challenge: edition.challenge, user: nil, game: nil,
        run: nil, edition: edition)
    end

    # Editions open on their own when sign-up is due, so each one stored has
    # opened.
    def self.signups_opened(challenges, per)
      editions(challenges).where(signup_opens_on: ..Challenges.today).order(signup_opens_on: :desc, id: :desc)
        .limit(per).map { |edition| edition_event("signups_opened", edition, edition.signup_opens_on) }
    end

    def self.edition_revealed(challenges, per)
      editions(challenges).where(phase: %w[revealed ended]).order(reveal_on: :desc, id: :desc).limit(per)
        .map { |edition| edition_event("edition_revealed", edition, edition.reveal_on) }
    end
    private_class_method :runs, :run_event, :run_started, :run_finished, :game_cleared, :editions, :edition_event,
      :signups_opened, :edition_revealed
  end
end
