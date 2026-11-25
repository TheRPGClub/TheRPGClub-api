# frozen_string_literal: true

# An Edition as the API serves it (spec #376, ticket #383): its year, phase
# and dates (the club's), and the members signed up, each marked when the
# draw left them out or they withdrew after it. From the reveal on it serves
# the assignments (ticket #384), with the Santas only once the Edition ends,
# except to staff not drawn in it. `params[:user_id]` is the member reading, for `signed_up`,
# `params[:staff]` whether they are staff (a Moderator or above), and
# `params[:viewer]` their backlog size against the sign-up minimum.
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

  # `picked`: while Santas pick, whether a game is picked for the member
  # (null outside the picking phase, and for members the draw left out).
  attribute :members do |edition|
    picked = ChallengeEditionResource.picked_recipients(edition)
    edition.signups.sort_by(&:signed_up_at).map do |signup|
      Challenges.member(signup.user).merge(left_out: signup.left_out?, withdrawn: signup.withdrawn?,
        picked: picked && (picked[signup.user_id] unless signup.left_out?))
    end
  end

  # How many recipients have a game picked while Santas pick; null otherwise.
  attribute :picked_count do |edition|
    ChallengeEditionResource.picked_recipients(edition)&.count { |_user_id, picked| picked }
  end

  attributes :drawn_at

  # Who gives what to whom (ticket #384), once the picks are revealed, and
  # to staff (`params[:staff]`) from the draw on: each recipient, the game
  # picked for them (null while nothing is), whether it was a random pick,
  # their Run and its progress, and their Santa, which nobody but staff
  # sees before the Edition ends. A staff member drawn in the Edition sees
  # it as a member would for themselves: no game of their own before the
  # reveal and no Santas before the end (ChallengeEdition#pick_shown?,
  # #santas_shown?). Null when not served.
  attribute :assignments do |edition|
    staff = params[:staff] ? true : false
    next nil unless edition.revealed? || (staff && edition.drawn?)

    viewer = { user_id: params[:user_id], staff: staff }
    santas = edition.santas_shown?(**viewer)
    runs = edition.runs.index_by(&:user_id)
    edition.signups.select(&:recipient_user_id).sort_by { |signup| signup.recipient.username.to_s.downcase }
      .map do |signup|
        run = runs[signup.recipient_user_id]
        pick = edition.pick_shown?(signup.recipient_user_id, **viewer)
        { recipient: Challenges.member(signup.recipient),
          game: pick && signup.picked_game ? GameSummaryResource.new(signup.picked_game).serializable_hash : nil,
          picked_randomly: (signup.picked_randomly if pick),
          santa: (Challenges.member(signup.user) if santas),
          run: run && { id: run.id, status: run.status, progress: Challenges::Progress.summary(run).as_json } }
      end
  end

  attributes :picks_closed_at

  # The member reading (`params[:viewer]`): their backlog size and whether
  # it meets the sign-up minimum. Null without a member, and in bot job
  # payloads.
  attribute :viewer do
    params[:viewer]
  end

  # While Santas pick, each recipient's user id => whether a game is picked
  # for them; nil in any other phase. A recipient stays picked when their
  # Santa withdraws after picking (Challenges::Picks.withdraw! keeps
  # `picked_at`), so the flag never changes when a Santa withdraws and
  # nobody can tell from it whose Santa they were. Neither the Santa nor
  # the game is served.
  def self.picked_recipients(edition)
    return unless edition.phase == "picking"

    edition.signups.select(&:recipient_user_id).to_h { |signup| [ signup.recipient_user_id, signup.picked_at.present? ] }
  end

  PRELOADS = [ :challenge, { signups: [ :user, :recipient, { picked_game: :images } ], runs: %i[entries challenge] } ].freeze

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
