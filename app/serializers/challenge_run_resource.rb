# frozen_string_literal: true

# A Run as the API serves it (spec #376, ticket #378): its Challenge and
# member, status, window (the club's dates, both ends included), progress
# (In Progress and Cleared games against the target) and the games counted
# on it, Cleared first. An Assignment Run names the Edition it was drawn in.
#
# Load Runs through ChallengeRunResource.preloaded.
class ChallengeRunResource
  include BaseResource

  attributes :id, :status, :started_at, :ended_at

  attribute :challenge do |run|
    challenge = run.challenge
    { id: challenge.id, name: challenge.name, challenge_format: challenge.challenge_format,
      schedule: challenge.schedule }
  end

  attribute :user do |run|
    user = run.user
    { user_id: user.user_id, username: user.username, global_name: user.global_name }
  end

  attribute :edition do |run|
    edition = run.edition
    edition && { id: edition.id, year: edition.year }
  end

  # Assignment only (null otherwise): the game picked for the member, and
  # whether at random, once revealed (or to staff, `params[:staff]`); and
  # their Santa, which nobody but staff sees before the Edition ends.
  attribute :assignment do |run|
    edition = run.edition
    next nil unless edition

    signup = run.assignment
    staff = params[:staff] ? true : false
    shown = signup && (edition.revealed? || staff)
    { game: shown && signup.picked_game ? GameSummaryResource.new(signup.picked_game).serializable_hash : nil,
      picked_randomly: shown ? signup.picked_randomly : nil,
      santa: signup && (staff || edition.ended?) ? ChallengeEditionResource.member(signup.user) : nil }
  end

  attribute :window do |run|
    run.window.as_json
  end

  attribute :progress do |run|
    Challenges::Progress.summary(run).as_json
  end

  attribute :entries do |run|
    run.entries.sort_by { |entry| [ entry.cleared? ? 0 : 1, entry.cleared_on || Date.new(0), entry.game.title.to_s ] }
      .map do |entry|
        { game_id: entry.game_id, title: entry.game.title, state: entry.state, cleared_on: entry.cleared_on&.iso8601,
          completion_id: entry.completion_id, slot_year: entry.slot_year, picked_by_hand: entry.picked_by_hand }
      end
  end

  attribute :slots do |run|
    Challenges::Formats::Slots.run_json(run) if run.challenge.challenge_format == Challenges::Formats::Slots::KEY
  end

  PRELOADS = [ :user, { edition: { signups: %i[user picked_game] }, entries: :game,
                         challenge: %i[pool_franchises pool_collections pool_games] } ].freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)
end
