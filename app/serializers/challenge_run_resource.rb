# frozen_string_literal: true

# A Run as the API serves it (spec #376, ticket #378): its Challenge (with
# its tint) and member, status, window (the club's dates, both ends
# included), progress (In Progress and Cleared games against the target)
# and the games counted on it, Cleared first. An Assignment Run names the Edition it was drawn in.
#
# Load Runs through ChallengeRunResource.preloaded.
class ChallengeRunResource
  include BaseResource

  attributes :id, :status, :started_at, :ended_at

  attribute :challenge do |run|
    challenge = run.challenge
    slots = challenge.challenge_format == Challenges::Formats::Slots::KEY
    { id: challenge.id, name: challenge.name, challenge_format: challenge.challenge_format,
      schedule: challenge.schedule, counts_past_play: challenge.counts_past_play, tint: challenge.tint.as_json,
      slots: (Challenges::Formats::Slots.as_json(challenge, Challenges::Formats::Slots.load(challenge)) if slots) }
  end

  attribute :user do |run|
    Challenges.member(run.user)
  end

  attribute :edition do |run|
    edition = run.edition
    edition && { id: edition.id, year: edition.year }
  end

  # Assignment only (null otherwise): the game picked for the member, and
  # whether at random, once revealed (or to staff, `params[:staff]`, but for
  # their own Run); and their Santa, which nobody but staff not drawn in the
  # Edition sees before it ends (ChallengeEdition#pick_shown?, #santas_shown?;
  # `params[:user_id]` is the member reading).
  attribute :assignment do |run|
    edition = run.edition
    next nil unless edition

    signup = run.assignment
    viewer = { user_id: params[:user_id], staff: params[:staff] ? true : false }
    shown = signup && edition.pick_shown?(run.user_id, **viewer)
    { game: shown && signup.picked_game ? GameSummaryResource.new(signup.picked_game).serializable_hash : nil,
      picked_randomly: shown ? signup.picked_randomly : nil,
      santa: signup && edition.santas_shown?(**viewer) ? Challenges.member(signup.user) : nil }
  end

  attribute :window do |run|
    run.window.as_json
  end

  attribute :progress do |run|
    Challenges::Progress.summary(run).as_json
  end

  # Each entry carries its game's cover, and on a Slots Run the years the
  # game fits (Challenges::ReleaseYears; null for the other Formats).
  attribute :entries do |run|
    slots = run.challenge.challenge_format == Challenges::Formats::Slots::KEY
    run.entries.sort_by { |entry| [ entry.cleared? ? 0 : 1, entry.cleared_on || Date.new(0), entry.game.title.to_s ] }
      .map do |entry|
        { game_id: entry.game_id, title: entry.game.title, cover_url: entry.game.cover_url, state: entry.state,
          cleared_on: entry.cleared_on&.iso8601, completion_id: entry.completion_id, slot_year: entry.slot_year,
          picked_by_hand: entry.picked_by_hand,
          release_years: (Challenges::ReleaseYears.of_game(entry.game) if slots) }
      end
  end

  attribute :slots do |run|
    Challenges::Formats::Slots.run_json(run) if run.challenge.challenge_format == Challenges::Formats::Slots::KEY
  end

  PRELOADS = [ :user, { edition: { signups: [ :user, { picked_game: :images } ] }, entries: { game: %i[images releases] },
                         challenge: %i[pool_franchises pool_collections pool_games] } ].freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)
end
