# frozen_string_literal: true

module Challenges
  # When play counts toward a Run (spec #376, "Counting rules"), as the
  # club's dates, both ends included: the Season the Run belongs to for a
  # Seasonal Challenge, and from the Run's start to the Challenge's end date
  # (open-ended without one) for an Always Open Challenge, and for an
  # Assignment Run, its Edition's year to Clear: from the reveal to the day
  # before the Edition ends on the next reveal date, when the Run Expires.
  Window = Data.define(:starts_on, :ends_on) do
    def self.for(run)
      if run.edition_id
        new(starts_on: run.edition.reveal_on, ends_on: run.edition.ends_on - 1)
      elsif run.season_starts_on
        new(starts_on: run.season_starts_on, ends_on: run.season_ends_on)
      else
        new(starts_on: Challenges.today(run.started_at), ends_on: run.challenge.ends_on)
      end
    end

    def include?(date) = date >= starts_on && (ends_on.nil? || date <= ends_on)

    # Whether the window has not ended by `date`.
    def open_on?(date) = ends_on.nil? || date <= ends_on

    def as_json(*) = { starts_on: starts_on.iso8601, ends_on: ends_on&.iso8601 }
  end
end
