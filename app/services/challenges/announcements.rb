# frozen_string_literal: true

module Challenges
  # What the API asks the bot to post about Challenges (spec #376, "Bot
  # jobs"). Kind `challenge_announce` posts publicly and is owned by the
  # `challenges` Feature (BotJob::PUBLIC_POST_FEATURES): the bot posts it in
  # the #challenges channel (a bot channel setting, like every Feature
  # channel), or in the staff test channel while the Feature is in Preview.
  #
  # Payload: { event, challenge, feature_key: "challenges" }. `challenge` is
  # the Challenge as GET /api/v1/challenges/{id} serves it. Events so far: "challenge_created". Later tickets add Season,
  # Edition and Run events with their own fields.
  module Announcements
    KIND = "challenge_announce"
    FEATURE_KEY = "challenges"

    # A new Challenge, requested by the member `by` (a Discord user id).
    def self.challenge_created!(challenge, by:)
      enqueue!("challenge_created", challenge, summary: %(Announce the new Challenge "#{challenge.name}"), by: by)
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
