# frozen_string_literal: true

# An Edition as the API serves it (spec #376, ticket #383): its year, phase
# and dates (the club's), and the members signed up, each marked when the
# draw left them out. Who gives to whom is never served here before the
# Edition ends (ticket #384 reveals it). `params[:user_id]` is the member
# reading, for `signed_up`.
#
# Load Editions through ChallengeEditionResource.preloaded.
class ChallengeEditionResource
  include BaseResource

  DATES = %i[signup_opens_on signup_cutoff_on pick_deadline_on reveal_on ends_on].freeze

  attributes :id, :year, :phase

  attribute :challenge do |edition|
    { id: edition.challenge.id, name: edition.challenge.name }
  end

  DATES.each do |field|
    attribute(field) { |edition| edition.public_send(field).iso8601 }
  end

  attribute :signup_open do |edition|
    edition.signup_open?(params[:today] || Challenges.today)
  end

  attribute :signed_up_count do |edition|
    edition.signups.size
  end

  attribute :signed_up do |edition|
    user_id = params[:user_id]
    user_id.present? && edition.signups.any? { |signup| signup.user_id == user_id }
  end

  attribute :members do |edition|
    edition.signups.sort_by(&:signed_up_at).map do |signup|
      user = signup.user
      { user_id: user.user_id, username: user.username, global_name: user.global_name, left_out: signup.left_out? }
    end
  end

  attributes :drawn_at

  PRELOADS = [ :challenge, { signups: :user } ].freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)

  # The Edition as GET /api/v1/challenge_editions/{id} serves it to nobody
  # in particular, for bot job payloads.
  def self.serialize(edition)
    new(preloaded(ChallengeEdition.where(id: edition.id)).first!).serializable_hash
  end

  # The Edition's year, phase and dates, as the Challenge shows its latest.
  def self.summary(edition)
    { id: edition.id, year: edition.year, phase: edition.phase,
      **DATES.to_h { |field| [ field, edition.public_send(field).iso8601 ] } }
  end
end
