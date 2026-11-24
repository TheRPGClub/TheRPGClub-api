# frozen_string_literal: true

module Challenges
  # The DMs the API asks the bot to send about Challenges (spec #376, "Bot
  # jobs"). Kind `challenge_dm` is owned by the `challenges` Feature but posts
  # nothing publicly (BotJob::FEATURE_WORK): the bot DMs the member `user_id`.
  # Reminders go only to members who keep Challenge DMs on
  # (`rpg_club_users.challenge_dms`, GET/PATCH
  # /api/v1/users/{user_id}/challenge_settings); news about the member's own
  # sign-up ("left_out_of_draw") goes to every member still in the server.
  #
  # Payload: { event, user_id, challenge, feature_key: "challenges", ... }.
  # `challenge` is the Challenge as GET /api/v1/challenges/{id} serves it.
  # Events so far: "season_ending", with the member's Run (as
  # GET /api/v1/challenge_runs/{id} serves it) under `run`, the Season's first
  # and last day under `season` ({ starts_on, ends_on }) and `days_left`, the
  # days from today to its last day; and "left_out_of_draw", a member the
  # draw left out of an Edition (as GET /api/v1/challenge_editions/{id} serves
  # it, under `edition`) for having `backlog_count` games in their backlog,
  # under the `minimum`; and "pick_reminder", a Santa who hasn't picked for
  # their `recipient` ({ user_id, username, global_name }) 2 days before the
  # Edition's pick deadline (`days_left`), with the Edition under `edition`;
  # and "pool_goal_changed", a Pool edit that grew the goal of the member's
  # Active Run (as GET /api/v1/challenge_runs/{id} serves it, under `run`):
  # the Core Games it added under `added_core_games` ({ game_id, title,
  # cover_url }, oldest release first) and a raised Optional target under
  # `optional_target` ({ from, to }, null when unchanged).
  module DirectMessages
    KIND = "challenge_dm"

    # The members whose Challenge DMs may be sent: still in the server and
    # not opted out.
    def self.reachable(users = RpgClubUser.all) = users.where(challenge_dms: true, server_left_at: nil)

    # Tells each member of `backlog_counts` (user id => games in their
    # backlog) that the draw left them out of `edition`. Queued by the
    # lifecycle job, so they have no requester.
    def self.left_out_of_draw!(edition, backlog_counts)
      users = RpgClubUser.where(user_id: backlog_counts.keys, server_left_at: nil).to_a
      return if users.empty?

      challenge = ChallengeResource.preloaded(Challenge.where(id: edition.challenge_id)).first!
      challenge_json = ChallengeResource.new(challenge, params: { detail: true }).serializable_hash
      edition_json = ChallengeEditionResource.serialize(edition)
      users.each do |user|
        BotJob.enqueue!(
          kind: KIND, summary: %(Tell #{Challenges.display_name(user)} they were left out of "#{challenge.name}" #{edition.year}),
          payload: { event: "left_out_of_draw", user_id: user.user_id, challenge: challenge_json,
                     edition: edition_json, backlog_count: backlog_counts.fetch(user.user_id),
                     minimum: Editions::BACKLOG_MINIMUM }
        )
      end
    end

    # Reminds each Santa of `signups` (sign-ups of `edition` without a pick)
    # to pick for their recipient before the deadline. Queued by the
    # lifecycle job, so they have no requester.
    def self.pick_reminder!(edition, signups, today:)
      signups = signups.preload(:user, :recipient).to_a
      return if signups.empty?

      challenge = ChallengeResource.preloaded(Challenge.where(id: edition.challenge_id)).first!
      challenge_json = ChallengeResource.new(challenge, params: { detail: true }).serializable_hash
      edition_json = ChallengeEditionResource.serialize(edition)
      signups.each do |signup|
        BotJob.enqueue!(
          kind: KIND, summary: %(Remind #{Challenges.display_name(signup.user)} to pick for "#{challenge.name}" #{edition.year}),
          payload: { event: "pick_reminder", user_id: signup.user_id, challenge: challenge_json, edition: edition_json,
                     recipient: Challenges.member(signup.recipient),
                     days_left: (edition.pick_deadline_on - today).to_i }
        )
      end
    end

    # Tells each member with an Active Run of `challenge` who keeps
    # Challenge DMs on that a Pool edit grew their goal: one DM per save,
    # naming the Core Games added and the raised target. Queued for the
    # member who edited (`challenge.updated_by`).
    def self.pool_goal_changed!(challenge, added_core_game_ids:, optional_target:)
      runs = challenge.runs.where(status: "active", user_id: reachable.select(:user_id))
      return unless runs.exists?

      challenge = ChallengeResource.preloaded(Challenge.where(id: challenge.id)).first!
      challenge_json = ChallengeResource.new(challenge, params: { detail: true }).serializable_hash
      added = GamedbGame.where(game_id: added_core_game_ids).preload(:images)
        .order(Arel.sql("initial_release_date ASC NULLS LAST, title ASC"))
        .map { |game| { game_id: game.game_id, title: game.title, cover_url: game.cover_url } }
      ChallengeRunResource.preloaded(runs).find_each do |run|
        BotJob.enqueue!(
          kind: KIND, requested_by: challenge.updated_by,
          summary: %(Tell #{Challenges.display_name(run.user)} the goal of "#{challenge.name}" changed),
          payload: { event: "pool_goal_changed", user_id: run.user_id, challenge: challenge_json,
                     run: ChallengeRunResource.new(run).serializable_hash, added_core_games: added,
                     optional_target: optional_target }
        )
      end
    end

    # Reminds the members of `runs` (Active Runs of `challenge`'s Season)
    # that the Season ends on `ends_on`. Queued by the lifecycle job, so they
    # have no requester.
    def self.season_ending!(challenge, runs, starts_on:, ends_on:, today:)
      challenge_json = ChallengeResource.new(challenge, params: { detail: true }).serializable_hash
      ChallengeRunResource.preloaded(runs).find_each do |run|
        BotJob.enqueue!(
          kind: KIND, summary: %(Remind #{Challenges.display_name(run.user)} that the Season of "#{challenge.name}" ends on #{ends_on.iso8601}),
          payload: { event: "season_ending", user_id: run.user_id, challenge: challenge_json,
                     run: ChallengeRunResource.new(run).serializable_hash,
                     season: { starts_on: starts_on.iso8601, ends_on: ends_on.iso8601 },
                     days_left: (ends_on - today).to_i }
        )
      end
    end
  end
end
