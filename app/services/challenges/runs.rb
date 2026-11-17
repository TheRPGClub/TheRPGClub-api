# frozen_string_literal: true

module Challenges
  # Starting, abandoning and deleting Runs (GLOSSARY.md, "Run"; ticket #378).
  # Each raises Challenges::RunRefused with the message members see.
  #
  #   start!     an Open Challenge, while the member has no Active Run of it;
  #              a Seasonal Run belongs to the Season it starts in. The new
  #              Run counts the member's play at once (a Seasonal Run counts
  #              play from earlier in its Season), so it may Finish straight
  #              away.
  #   abandon!   an Active Run; it stays, Abandoned, until deleted
  #   delete!    a Finished, Expired or Abandoned Run
  module Runs
    CLOSED = "This Challenge is Closed, so no Run can start now."
    ACTIVE = "You already have an Active Run of this Challenge."
    NOT_ACTIVE = "Only an Active Run can be abandoned."
    DELETE_ACTIVE = "Abandon this Run before deleting it."

    def self.start!(challenge, user_id, now: Time.current)
      today = Challenges.today(now)
      raise RunRefused.new("challenge_closed", CLOSED) unless challenge.open?(today)

      season = challenge.seasonal? ? challenge.schedule_rules.season_on(today) : nil
      run = ChallengeRun.transaction do
        refuse_active!(challenge, user_id)
        created = ChallengeRun.create!(challenge: challenge, user_id: user_id, started_at: now,
          season_starts_on: season&.first, season_ends_on: season&.last)
        Challenges.refresh_runs!(user_id)
        created
      end
      run.reload
    rescue ActiveRecord::RecordNotUnique
      # Another request started one between the check and the insert.
      refuse_active!(challenge, user_id)
      raise
    end

    def self.abandon!(run, now: Time.current)
      run.with_lock do
        raise RunRefused.new("run_not_active", NOT_ACTIVE) unless run.active?

        run.update!(status: "abandoned", ended_at: now)
      end
      run
    end

    def self.delete!(run)
      run.with_lock do
        raise RunRefused.new("run_active", DELETE_ACTIVE) if run.active?

        run.destroy!
      end
    end

    def self.refuse_active!(challenge, user_id)
      active = ChallengeRun.active.find_by(challenge_id: challenge.id, user_id: user_id)
      raise RunRefused.new("run_active", ACTIVE, run_id: active.id) if active
    end
    private_class_method :refuse_active!
  end
end
