# frozen_string_literal: true

# An Edition (GLOSSARY.md, "Edition"): one yearly cycle of an Assignment
# Challenge, named by the year of its reveal. Its concrete dates come from the
# Challenge's calendar when it opens (Challenges::Editions), as the club's
# dates: sign-up opens on `signup_opens_on` and closes at the start of
# `signup_cutoff_on`, when the draw happens; Santas pick before
# `pick_deadline_on`; the picks are revealed on `reveal_on`; and the Edition
# ends on `ends_on`, the next reveal date, one year later.
#
# Its phase: signup, picking (drawn), revealed, ended, or cancelled (fewer
# than 2 members could be drawn).
class ChallengeEdition < ApplicationRecord
  PHASES = %w[signup picking revealed ended cancelled].freeze

  belongs_to :challenge, inverse_of: :editions
  has_many :signups, class_name: "ChallengeEditionSignup", foreign_key: :edition_id, dependent: nil,
    inverse_of: :edition
  has_many :runs, class_name: "ChallengeRun", foreign_key: :edition_id, dependent: nil, inverse_of: :edition

  validates :phase, inclusion: { in: PHASES }

  scope :in_signup, -> { where(phase: "signup") }

  # Whether members may sign up or withdraw on the club date `today`.
  def signup_open?(today = Challenges.today) = phase == "signup" && today < signup_cutoff_on
end
