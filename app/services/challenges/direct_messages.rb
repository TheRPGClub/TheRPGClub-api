# frozen_string_literal: true

module Challenges
  # The DMs the API asks the bot to send about Challenges (spec #376, "Bot
  # jobs"). Kind `challenge_dm` is owned by the `challenges` Feature but posts
  # nothing publicly (BotJob::FEATURE_WORK): the bot DMs the member `user_id`.
  # Only members who keep Challenge DMs on (`rpg_club_users.challenge_dms`,
  # GET/PATCH /api/v1/users/{user_id}/challenge_settings) are sent one.
  #
  # Payload: { event, user_id, challenge, feature_key: "challenges", ... }.
  # `challenge` is the Challenge as GET /api/v1/challenges/{id} serves it.
  # Events so far: "season_ending", with the member's Run (as
  # GET /api/v1/challenge_runs/{id} serves it) under `run`, the Season's first
  # and last day under `season` ({ starts_on, ends_on }) and `days_left`, the
  # days from today to its last day. The Secret Santa tickets add theirs.
  module DirectMessages
    KIND = "challenge_dm"

    # The members whose Challenge DMs may be sent: still in the server and
    # not opted out.
    def self.reachable(users = RpgClubUser.all) = users.where(challenge_dms: true, server_left_at: nil)

    # Reminds the members of `runs` (Active Runs of `challenge`'s Season)
    # that the Season ends on `ends_on`. Queued by the lifecycle job, so they
    # have no requester.
    def self.season_ending!(challenge, runs, starts_on:, ends_on:, today:)
      challenge_json = ChallengeResource.new(challenge, params: { detail: true }).serializable_hash
      ChallengeRunResource.preloaded(runs).find_each do |run|
        member = run.user.global_name.presence || run.user.username.presence || run.user_id
        BotJob.enqueue!(
          kind: KIND, summary: %(Remind #{member} that the Season of "#{challenge.name}" ends on #{ends_on.iso8601}),
          payload: { event: "season_ending", user_id: run.user_id, challenge: challenge_json,
                     run: ChallengeRunResource.new(run).serializable_hash,
                     season: { starts_on: starts_on.iso8601, ends_on: ends_on.iso8601 },
                     days_left: (ends_on - today).to_i }
        )
      end
    end
  end
end
