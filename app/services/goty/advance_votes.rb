# frozen_string_literal: true

module Goty
  # The GOTY Vote's lifecycle (spec api#471, ticket api#475), run by the
  # every-minute voting sweep (Voting::AdvanceRoundsJob) next to the GOTM
  # round's. It creates year Y's GOTY Vote on 1 January of Y (spec api#481;
  # the first sweep after a deploy catches up the current year), queues the
  # bot's posts as their moment arrives, freezes the candidates when voting
  # opens, closes the vote, and settles the runoff. Each post is queued once
  # per GOTY Vote (the outbox's unique year/kind index) and each step acts
  # once (Goty::Decide), so running late or twice is harmless; a late sweep
  # skips a post whose window has passed (a nomination reminder after voting
  # opened). A no-op while Voting.automation_enabled? is off.
  #
  # Event sequence: goty_nominations_opened, goty_nomination_reminder_5d and
  # _1d, goty_voting_opened, then goty_decided, or goty_runoff_opened when an
  # Award tied. The runoff's close queues goty_runoff_closed, then
  # goty_decided, or goty_tie_pending when an Award tied again and waits on
  # an admin (whose pick queues goty_decided, Goty::Decide.resolve_tie!).
  module AdvanceVotes
    REMINDERS = { "goty_nomination_reminder_5d" => 5, "goty_nomination_reminder_1d" => 1 }.freeze

    module_function

    def call(now: Time.current)
      return unless Voting.automation_enabled?

      missing_years(now).each { |year| GotyVote.ensure!(year) }
      GotyVote.where(decided_at: nil).order(:year).each { |vote| advance(vote, now) }
    end

    # When the sweep next has GOTY Vote work, as for
    # Voting::AdvanceRounds.next_event_at: a post already queued, or whose
    # window has passed, is skipped, and work already due reports `now`. nil
    # while automation is off.
    def next_event_at(now: Time.current)
      return unless Voting.automation_enabled?

      votes = GotyVote.where(decided_at: nil).to_a
      queued = VotingEvent.where(goty_year: votes.map(&:year)).pluck(:goty_year, :kind)
      upcoming = votes.flat_map do |vote|
        scheduled_events(vote).filter_map do |kind, at, closes_at|
          at unless at.nil? || queued.include?([ vote.year, kind ]) || (closes_at && now >= closes_at)
        end
      end
      upcoming << creation_due_at(now)
      [ upcoming.compact.min, now ].max
    end

    # The years whose GOTY Vote should exist at `now` but does not: this
    # year's (ET) all year round, and last year's in January until its
    # default voting open, should it never have been created. A year is
    # never created with its windows already past.
    def missing_years(now)
      local = now.in_time_zone(Voting::Schedule::TIME_ZONE)
      years = [ local.year ]
      years.unshift(local.year - 1) if now < Goty::Schedule.voting_opens_at(local.year - 1)
      years - GotyVote.where(year: years).pluck(:year)
    end

    # When the next GOTY Vote is due to be created: now when one is missing,
    # else 1 January (ET) of the first later year without one.
    def creation_due_at(now)
      return now if missing_years(now).any?

      year = now.in_time_zone(Voting::Schedule::TIME_ZONE).year + 1
      year += 1 while GotyVote.exists?(year: year)
      Date.new(year, 1, 1).in_time_zone(Voting::Schedule::TIME_ZONE)
    end

    # [kind, due at, window closes at] for each step #advance takes on the
    # clock, as far as the vote's state still allows it. "freeze", "close"
    # and "close_runoff" are steps rather than posts, so never queued.
    def scheduled_events(vote)
      events = [ [ "goty_nominations_opened", vote.nominations_open_at, vote.voting_opens_at ] ]
      reminders(vote).each { |kind, at, _days_before| events << [ kind, at, vote.voting_opens_at ] }
      events << [ "goty_voting_opened", vote.voting_opens_at, vote.voting_closes_at ]
      events << [ "freeze", vote.voting_opens_at, nil ] if vote.candidates_frozen_at.nil?
      events << [ "close", vote.voting_closes_at, nil ] if vote.closed_at.nil?
      events << [ "close_runoff", vote.runoff_closes_at, nil ] if vote.runoff_closed_at.nil?
      events
    end

    def advance(vote, now)
      queue_nomination_events(vote, now)
      open_voting(vote, now)
      if vote.closed_at.nil?
        close(vote, now) if vote.voting_ended?(now)
      elsif vote.runoff_ended?(now) && vote.runoff_closed_at.nil?
        close_runoff(vote, now)
      end
    end

    def queue_nomination_events(vote, now)
      return unless vote.nominations_open?(now)

      emit(vote, "goty_nominations_opened", available_at: vote.nominations_open_at,
        expires_at: vote.voting_opens_at)
      reminders(vote).each do |kind, at, days_before|
        next if now < at

        emit(vote, kind, available_at: at, expires_at: vote.voting_opens_at, days_before: days_before)
      end
    end

    # [kind, due at, days before voting] for each nomination reminder. One
    # that would fall before nominations open (dates moved closer together)
    # is never posted: it would remind of nominations not yet open.
    def reminders(vote)
      REMINDERS.filter_map do |kind, days_before|
        at = Voting::Schedule.reminder_at(vote.voting_opens_at, days_before)
        [ kind, at, days_before ] unless at < vote.nominations_open_at
      end
    end

    # Freezing may already have happened (a cast or Decide.close! freezes
    # first when the sweep is late), so the post hangs on the window, not on
    # whether this call froze; the outbox queues it once either way.
    def open_voting(vote, now)
      return if now < vote.voting_opens_at

      Goty::FreezeCandidates.call(vote, now: now)
      return unless vote.voting_open?(now)

      emit(vote, "goty_voting_opened", available_at: vote.voting_opens_at, expires_at: vote.voting_closes_at)
    end

    def close(vote, now)
      Goty::Decide.close!(vote, now: now) do |record|
        if record.decided_at
          queue_decided(record, now)
        else
          emit(record, "goty_runoff_opened", available_at: now, expires_at: record.runoff_closes_at)
        end
      end
    end

    def close_runoff(vote, now)
      Goty::Decide.close_runoff!(vote, now: now) do |record|
        emit(record, "goty_runoff_closed", available_at: now)
        record.decided_at ? queue_decided(record, now) : emit(record, "goty_tie_pending", available_at: now)
      end
    end

    # Queues the results post. Also the admin tie pick's, from inside
    # Goty::Decide.resolve_tie!'s block once the pick decided the vote.
    def queue_decided(vote, now = Time.current)
      emit(vote, "goty_decided", available_at: now)
    end

    # Builds the payload only for a post not yet queued.
    def emit(vote, kind, available_at:, expires_at: nil, **extra)
      return if VotingEvent.exists?(goty_year: vote.year, kind: kind)

      VotingEvent.emit!(goty_year: vote.year, kind: kind, available_at: available_at, expires_at: expires_at,
        payload: Goty::EventPayload.for(vote, kind, **extra))
    end
  end
end
