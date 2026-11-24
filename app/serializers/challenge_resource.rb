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
    format.as_json(challenge, format.load(challenge), detail: params[:detail] ? true : false)
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

  attribute :key_art_url do |challenge|
    Challenges::KeyArt.url(challenge) if params[:detail]
  end

  attributes :hidden, :ended_at, :created_by, :updated_by, :created_at, :updated_at

  PRELOADS = [ :host, :editions, { pool_franchises: :franchise, pool_collections: :collection, pool_games: { game: :images } } ]
    .freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)

  private

  def overview_of(challenge)
    overview = params[:overview]
    return overview if overview&.covers?(challenge)

    (@overviews ||= {})[challenge.id] ||= Challenges::Overview.of([ challenge ])
  end
end
