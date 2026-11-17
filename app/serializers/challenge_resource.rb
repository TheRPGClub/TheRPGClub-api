# frozen_string_literal: true

# A Challenge as the API serves it (spec #376): its text, Host, Challenge
# Format, schedule, whether it is Open today (in the club's time zone), and
# its Format's settings under the Format's key (Challenges::Formats).
#
# Load Challenges through ChallengeResource.preloaded so the Host and the
# Pool's names come in a few queries. `params[:detail]` (the show) adds the
# Pool's `game_count` and `run_count`.
class ChallengeResource
  include BaseResource

  attributes :id, :name, :description, :challenge_format

  attribute :hosted_by_club, &:club_hosted?

  attribute :host do |challenge|
    host = challenge.host
    host && { user_id: host.user_id, username: host.username, global_name: host.global_name }
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

  attribute :run_count do |challenge|
    challenge.runs.size if params[:detail]
  end

  attributes :hidden, :created_by, :updated_by, :created_at, :updated_at

  PRELOADS = [ :host, { pool_franchises: :franchise, pool_collections: :collection, pool_games: :game } ].freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)
end
