# frozen_string_literal: true

module Voting
  # The recurring sweep behind the round lifecycle (Voting::AdvanceRoundsJob):
  # queues the bot's posts as their moment arrives and decides the current
  # round once its voting window has closed. Idempotent — each event is queued
  # once per round and a round is decided once — so running it late or twice
  # is harmless. A no-op while Voting.automation_enabled? is off.
  module AdvanceRounds
    REMINDERS = { "nomination_reminder_5d" => 5, "nomination_reminder_1d" => 1 }.freeze

    module_function

    def call(now: Time.current)
      return unless Voting.automation_enabled?

      round = VotingRound.current
      return if round.nil?

      queue_nomination_reminders(round, now)
      queue_voting_opened(round, now)
      decide(round, now) if round.voting_ended?(now) && round.closed_at.nil?
    end

    def queue_nomination_reminders(round, now)
      return unless round.nominations_open?(now)

      REMINDERS.each do |kind, days_before|
        at = Schedule.reminder_at(round.voting_opens_at, days_before)
        next if now < at

        VotingEvent.emit!(round_number: round.round_number, kind: kind, available_at: at,
          expires_at: round.voting_opens_at, payload: { voting_opens_at: round.voting_opens_at })
      end
    end

    def queue_voting_opened(round, now)
      return unless round.voting_open?(now)

      VotingEvent.emit!(round_number: round.round_number, kind: "voting_opened",
        available_at: round.voting_opens_at, expires_at: round.voting_closes_at,
        payload: { voting_closes_at: round.voting_closes_at })
    end

    def decide(round, now)
      result = DecideRound.new(round, now: now).call
      payload = { winners: result.winners, ties: result.ties }

      VotingEvent.emit!(round_number: round.round_number, kind: "voting_closed", available_at: now, payload: payload)
      if result.ties.present?
        VotingEvent.emit!(round_number: round.round_number, kind: "tie_pending", available_at: now, payload: payload)
      else
        VotingEvent.emit!(round_number: round.round_number, kind: "round_decided", available_at: now, payload: payload)
      end
    end
  end
end
