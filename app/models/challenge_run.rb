# frozen_string_literal: true

# A Run (GLOSSARY.md, "Run"): one member's attempt at a Challenge, with its
# own progress. Its status is Active, then Finished, Expired or Abandoned;
# only one Active Run per member per Challenge (ux_challenge_runs_one_active).
#
# Its window is when play counts toward it (Challenges::Window): from its
# start to the Challenge's end date for an Always Open Challenge, and the
# Season it was started in for a Seasonal one (`season_starts_on` to
# `season_ends_on`). Its entries are the games counted on it, kept up to
# date by Challenges::Progress.
#
# A Slots Run copies its `first_year` when it starts (the fixed one, or the
# member's birth year) and keeps it. Caught Up is worked out, never stored;
# `caught_up_announced_year` is only the year it was last announced, so it is
# announced at most once a year.
#
# An Assignment Run belongs to the Edition it was drawn in (`edition_id`),
# which sets its window. Editions overlap, so a member may have an Active Run
# in two Editions of the same Challenge; the one-Active-Run rule is for Runs
# outside an Edition.
class ChallengeRun < ApplicationRecord
  STATUSES = %w[active finished expired abandoned].freeze
  # The statuses a member may delete a Run in; an Active Run is abandoned first.
  ENDED = %w[finished expired abandoned].freeze

  belongs_to :challenge, inverse_of: :runs
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id,
    inverse_of: false
  has_many :entries, class_name: "ChallengeRunEntry", foreign_key: :run_id, dependent: nil, inverse_of: :run
  belongs_to :edition, class_name: "ChallengeEdition", optional: true, inverse_of: :runs

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def active? = status == "active"

  def finished? = status == "finished"

  def window = Challenges::Window.for(self)

  # An Assignment Run's sign-up row naming the game picked for its member
  # (ChallengeEditionSignup, the Santa's), or nil.
  def assignment
    edition&.signups&.find { |signup| signup.recipient_user_id == user_id }
  end
end
