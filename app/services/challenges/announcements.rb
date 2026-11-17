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
  # "challenge_created", and "run_finished" and "run_caught_up" with the Run
  # (as GET /api/v1/challenge_runs/{id} serves it) under `run`. Later tickets
  # add Season and Edition events with their own fields.
  module Announcements
    KIND = "challenge_announce"
    FEATURE_KEY = "challenges"

    # A new Challenge, requested by the member `by` (a Discord user id).
    def self.challenge_created!(challenge, by:)
      enqueue!("challenge_created", challenge, summary: %(Announce the new Challenge "#{challenge.name}"), by: by)
    end

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
