# frozen_string_literal: true

module Voting
  # The recurring sweep behind the round lifecycle (Voting::AdvanceRoundsJob):
  # queues the bot's posts as their moment arrives, decides the current round
  # once its voting window has closed, and settles its runoff once that
  # closes. Idempotent — each event is queued once per round and a round (and
  # its runoff) is decided once — so running it late or twice is harmless. A
  # no-op while Voting.automation_enabled? is off.
  #
  # Event sequence: voting_closed, then round_decided, or runoff_opened when a
  # category tied. The runoff's close queues runoff_closed, then round_decided,
  # or tie_pending when the runoff tied again and waits on an admin.
  module AdvanceRounds
    REMINDERS = { "nomination_reminder_5d" => 5, "nomination_reminder_1d" => 1 }.freeze

    module_function

    def call(now: Time.current)
      return unless Voting.automation_enabled?

      round = VotingRound.current
      return if round.nil?

      queue_nomination_reminders(round, now)
      queue_voting_opened(round, now)
      if round.closed_at.nil?
        decide(round, now) if round.voting_ended?(now)
      elsif round.runoff_ended?(now) && round.runoff_closed_at.nil?
        decide_runoff(round, now)
      end
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
        VotingEvent.emit!(round_number: round.round_number, kind: "runoff_opened", available_at: now,
          expires_at: round.runoff_closes_at,
          payload: { ties: round.runoff_ties, runoff_closes_at: round.runoff_closes_at })
      else
        VotingEvent.emit!(round_number: round.round_number, kind: "round_decided", available_at: now, payload: payload)
      end
    end

    def decide_runoff(round, now)
      result = DecideRunoff.new(round, now: now).call

      VotingEvent.emit!(round_number: round.round_number, kind: "runoff_closed", available_at: now,
        payload: { winners: result.winners, ties: result.ties })
      if result.ties.present?
        VotingEvent.emit!(round_number: round.round_number, kind: "tie_pending", available_at: now,
          payload: { winners: Winners.for_round(round.round_number), ties: result.ties })
      else
        VotingEvent.emit!(round_number: round.round_number, kind: "round_decided", available_at: now,
          payload: { winners: Winners.for_round(round.round_number), ties: {} })
      end
    end
  end
end
