# frozen_string_literal: true

# A Challenge as the API serves it (spec #376): its text, Host, Challenge
# Format, schedule, whether it is Open today (in the club's time zone), and
# its Format's settings under the Format's key (Challenges::Formats).
#
# Load Challenges through ChallengeResource.preloaded so the Host, the
# Pool's names and an Assignment's Editions come in a few queries.
# `params[:detail]` (the show) adds the Pool's Optional Games and counts
# (Challenges::Formats::Pool.as_json) and `key_art_url`
# (Challenges::KeyArt; one query, so lists leave it null). Lists pass
# `params[:overview]` (Challenges::Overview.of the page) for `run_count`,
# `finished_count` and `pool_games`; a single Challenge reads its own.
# `params[:actor]` (a Challenges::Actor, the reader) sets the linked Game
# List's `visible` and `can_add`; on the show (`detail`) it also adds
# `pending_proposals` and `list_notices` for a Pool Challenge the actor
# decides Pool Proposals for.
class ChallengeResource
  include BaseResource

  attributes :id, :name, :description, :challenge_format

  attribute :hosted_by_club, &:club_hosted?

  attribute :host do |challenge|
    challenge.host && Challenges.member(challenge.host)
  end

  attribute :schedule do |challenge|
    challenge.schedule_rules.as_json[:schedule]
  end

  attribute :ends_on do |challenge|
    challenge.ends_on&.iso8601
  end

  attribute :season do |challenge|
    challenge.schedule_rules.as_json[:season]
  end

  attribute :open do |challenge|
    challenge.open?(params[:today] || Challenges.today)
  end

  attribute :pool do |challenge|
    next nil unless challenge.challenge_format == Challenges::Formats::Pool::KEY

    format = Challenges::Formats::Pool
    format.as_json(challenge, format.load(challenge), detail: params[:detail] ? true : false, viewer: params[:actor])
  end

  attribute :slots do |challenge|
    next nil unless challenge.challenge_format == Challenges::Formats::Slots::KEY

    format = Challenges::Formats::Slots
    format.as_json(challenge, format.load(challenge))
  end

  attribute :assignment do |challenge|
    next nil unless challenge.challenge_format == Challenges::Formats::Assignment::KEY

    format = Challenges::Formats::Assignment
    format.as_json(challenge, format.load(challenge))
  end

  attribute :tint do |challenge|
    challenge.tint.as_json
  end

  attribute :run_count do |challenge|
    overview_of(challenge).run_count(challenge)
  end

  attribute :finished_count do |challenge|
    overview_of(challenge).finished_count(challenge)
  end

  attribute :pool_games do |challenge|
    overview_of(challenge).pool_games_of(challenge)
  end

  attribute :pending_proposals do |challenge|
    next nil unless decider?(challenge)

    ChallengePoolProposal.pending.where(challenge_id: challenge.id).count
  end

  # The open list notices: Core Games whose entry left the linked list.
  attribute :list_notices do |challenge|
    next nil unless decider?(challenge)

    ChallengePoolListNotice.where(challenge_id: challenge.id).preload(game: :images).order(:created_at, :id)
      .map do |notice|
        game = notice.game
        { id: notice.id, game: { game_id: game.game_id, title: game.title, cover_url: game.cover_url },
          created_at: notice.created_at }
      end
  end

  attribute :key_art_url do |challenge|
    Challenges::KeyArt.url(challenge) if params[:detail]
  end

  attributes :hidden, :ended_at, :created_by, :updated_by, :created_at, :updated_at

  PRELOADS = [ :host, :editions, :pool_game_list, { pool_franchises: :franchise, pool_collections: :collection, pool_games: { game: :images } } ]
    .freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)

  private

  # On the show, whether the actor decides Pool Proposals for this Pool.
  def decider?(challenge)
    actor = params[:actor]
    params[:detail] && actor && challenge.challenge_format == Challenges::Formats::Pool::KEY &&
      actor.can_decide_proposals?(challenge)
  end

  def overview_of(challenge)
    overview = params[:overview]
    return overview if overview&.covers?(challenge)

    (@overviews ||= {})[challenge.id] ||= Challenges::Overview.of([ challenge ])
  end
end
