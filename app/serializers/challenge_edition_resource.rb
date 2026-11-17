# frozen_string_literal: true

# An Edition as the API serves it (spec #376, ticket #383): its year, phase
# and dates (the club's), and the members signed up, each marked when the
# draw left them out or they withdrew after it. From the reveal on it serves
# the assignments (ticket #384), with the Santas only once the Edition ends,
# except to staff. `params[:user_id]` is the member reading, for `signed_up`,
# and `params[:staff]` whether they are staff (a Moderator or above).
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
      Challenges.member(signup.user).merge(left_out: signup.left_out?, withdrawn: signup.withdrawn?)
    end
  end

  attributes :drawn_at

  # Who gives what to whom (ticket #384), once the picks are revealed, and
  # to staff (`params[:staff]`) from the draw on: each recipient, the game
  # picked for them (null while nothing is), whether it was a random pick,
  # their Run and its progress, and their Santa, which nobody but staff
  # sees before the Edition ends. Null when not served.
  attribute :assignments do |edition|
    staff = params[:staff] ? true : false
    next nil unless edition.revealed? || (staff && edition.drawn?)

    runs = edition.runs.index_by(&:user_id)
    edition.signups.select(&:recipient_user_id).sort_by { |signup| signup.recipient.username.to_s.downcase }
      .map do |signup|
        run = runs[signup.recipient_user_id]
        { recipient: Challenges.member(signup.recipient),
          game: signup.picked_game && GameSummaryResource.new(signup.picked_game).serializable_hash,
          picked_randomly: signup.picked_randomly,
          santa: (Challenges.member(signup.user) if staff || edition.ended?),
          run: run && { id: run.id, status: run.status, progress: Challenges::Progress.summary(run).as_json } }
      end
  end

  attributes :picks_closed_at

  PRELOADS = [ :challenge, { signups: %i[user recipient picked_game], runs: %i[entries challenge] } ].freeze

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
