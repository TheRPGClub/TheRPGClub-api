# frozen_string_literal: true

module Challenges
  # What the API asks the bot to post about Challenges (spec #376, "Bot
  # jobs"). Kind `challenge_announce` posts publicly and is owned by the
  # `challenges` Feature (BotJob::PUBLIC_POST_FEATURES): the bot posts it in
  # the #challenges channel (a bot channel setting, like every Feature
  # channel), or in the staff test channel while the Feature is in Preview.
  #
  # Payload: { event, challenge, feature_key: "challenges" }. `challenge` is
  # the Challenge as GET /api/v1/challenges/{id} serves it. Events so far:
  # "challenge_created"; "run_finished" and "run_caught_up" (Slots) with the
  # Run (as GET /api/v1/challenge_runs/{id} serves it) under `run`; and
  # "season_opened" with the Season's first and last day under `season`
  # ({ starts_on, ends_on }). An Assignment Challenge's Edition events carry
  # the Edition (as GET /api/v1/challenge_editions/{id} serves it) under
  # `edition`: "signup_opened"; "signup_closing" with `days_left` to the
  # cutoff; and, from the draw, "signup_closed" or "edition_cancelled" (fewer
  # than 2 members drawn), each with `joined`, the members drawn, and
  # `left_out`, those the backlog minimum left out.
  module Announcements
    KIND = "challenge_announce"
    FEATURE_KEY = "challenges"

    # A new Challenge, requested by the member `by` (a Discord user id).
    def self.challenge_created!(challenge, by:)
      enqueue!("challenge_created", challenge, summary: %(Announce the new Challenge "#{challenge.name}"), by: by)
    end

    # A Seasonal Challenge's Season opened (Challenges::Lifecycle::SeasonOpened),
    # with its first and last day under `season`. Queued by the lifecycle
    # job, so it has no requester.
    def self.season_opened!(challenge, starts_on:, ends_on:)
      enqueue!("season_opened", challenge, summary: %(Announce that the Season of "#{challenge.name}" is open),
        by: nil, season: { starts_on: starts_on.iso8601, ends_on: ends_on.iso8601 })
    end

    # An Edition's sign-up opened (Challenges::Lifecycle::EditionOpened).
    def self.signup_opened!(edition)
      edition_event!("signup_opened", edition, "Announce that sign-up for %<name>s %<year>d is open")
    end

    # An Edition's sign-up closes in `days_left` days
    # (Challenges::Lifecycle::SignupClosing).
    def self.signup_closing!(edition, today:)
      edition_event!("signup_closing", edition, "Announce that sign-up for %<name>s %<year>d closes soon",
        days_left: (edition.signup_cutoff_on - today).to_i)
    end

    # The draw (Challenges::Editions.draw!): `joined` members drawn, and
    # `left_out` below the backlog minimum.
    def self.signup_closed!(edition, joined:, left_out:)
      edition_event!("signup_closed", edition, "Announce that sign-up for %<name>s %<year>d closed",
        joined: joined, left_out: left_out)
    end

    # The draw cancelled the Edition: fewer than 2 members could be drawn.
    def self.edition_cancelled!(edition, joined:, left_out:)
      edition_event!("edition_cancelled", edition, "Announce that %<name>s %<year>d is cancelled",
        joined: joined, left_out: left_out)
    end

    # The Edition steps are queued by the lifecycle job, so they have no
    # requester.
    def self.edition_event!(event, edition, summary, **fields)
      challenge = ChallengeResource.preloaded(Challenge.where(id: edition.challenge_id)).first!
      enqueue!(event, challenge, summary: format(summary, name: %("#{challenge.name}"), year: edition.year), by: nil,
        edition: ChallengeEditionResource.serialize(edition), **fields)
    end
    private_class_method :edition_event!

    # A Run whose status changed (Challenges::Progress::Change): a Run that
    # became Finished (event "run_finished") or Caught Up (event
    # "run_caught_up", Slots), with the Run and its progress under `run`.
    def self.run_changed!(change)
      run = change.run
      challenge = ChallengeResource.preloaded(Challenge.where(id: run.challenge_id)).first!
      run = ChallengeRunResource.preloaded(ChallengeRun.where(id: run.id)).first!
      member = run.user.global_name.presence || run.user.username.presence || run.user_id
      done = change.event == "run_caught_up" ? "is Caught Up on" : "Finished"
      enqueue!(change.event, challenge, summary: %(Announce that #{member} #{done} "#{challenge.name}"),
        by: run.user_id, run: ChallengeRunResource.new(run).serializable_hash)
    end

    def self.enqueue!(event, challenge, summary:, by:, **fields)
      BotJob.enqueue!(
        kind: KIND, summary: summary, requested_by: by,
        payload: { event: event,
                   challenge: ChallengeResource.new(challenge, params: { detail: true }).serializable_hash, **fields }
      )
    end
    private_class_method :enqueue!
  end
end
