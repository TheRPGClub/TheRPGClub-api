# frozen_string_literal: true

module Challenges
  # The timed side of Challenges (spec #376, "Lifecycle job"), swept by
  # Challenges::LifecycleJob. Every date is the club's (Challenges.today).
  #
  #   Challenges::Lifecycle.call(now:)            takes every step that is due
  #   Challenges::Lifecycle.next_event_at(now:)   when one next comes due
  #
  # The work is a list of steps (STEPS). Each step is a module answering
  #
  #   call(today:, now:)    takes the step wherever it is due on `today`;
  #                         repeating it the same day changes nothing
  #   next_due_on(today)    the club date it next has work (today when it
  #                         has work now), or nil when it has none
  #
  # A step that must happen once per occasion (an announcement, a batch of
  # reminders) records it with Lifecycle.once!, keyed by the Challenge, the
  # step's name and the club date it was due on; a step that changes state
  # (expiring Runs) is safe to repeat by itself. A missed tick is caught up
  # by the next one, since each step does what fell due up to `today`.
  #
  # The Assignment Format's Edition steps (#383: EditionOpened,
  # SignupClosing, EditionDrawn; #384 adds the picks, the reveal and the
  # Edition's end) are added to STEPS the same way.
  module Lifecycle
    STEPS = [ SeasonOpened, SeasonEndingReminder, SeasonEnded, EndDateReached, EditionOpened, SignupClosing,
      EditionDrawn ].freeze

    module_function

    def call(now: Time.current)
      today = Challenges.today(now)
      STEPS.each { |step| step.call(today: today, now: now) }
    end

    # When the sweep next has work, so the job can skip the minutes until
    # then (Challenges::SweepSchedule): the start of the club day the first
    # step comes due on, or `now` when one is due already. nil when no step
    # has anything scheduled.
    def next_event_at(now: Time.current)
      today = Challenges.today(now)
      due_on = STEPS.filter_map { |step| step.next_due_on(today) }.min
      [ due_on.in_time_zone(TIME_ZONE), now ].max if due_on
    end

    # Takes `step` for `challenge` on the club date `on` once: records it and
    # runs the block in one transaction, or does nothing when it was taken
    # before. Returns whether it ran.
    def once!(challenge, step, on:)
      ChallengeLifecycleStep.transaction do
        recorded = ChallengeLifecycleStep.insert_all(
          [ { challenge_id: challenge.id, step: step, occurs_on: on } ], returning: %i[id]
        ).length.positive?
        yield if recorded && block_given?
        recorded
      end
    end

    # The [challenge_id, occurs_on] pairs of `step` taken on or after `since`.
    def taken(step, since:)
      ChallengeLifecycleStep.where(step: step, occurs_on: since..).pluck(:challenge_id, :occurs_on).to_set
    end

    # Each Seasonal Challenge of `scope` with the first and last day of its
    # Season in progress on `today`, or of its next one.
    def seasons(scope, today)
      scope.where(schedule: "seasonal").map { |challenge| [ challenge, challenge.schedule_rules.season_through(today) ] }
    end

    # The first and last day of the Season after the one ending on `ends_on`.
    def next_season(challenge, ends_on) = challenge.schedule_rules.season_through(ends_on + 1)
  end
end
