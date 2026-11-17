# frozen_string_literal: true

# A Run (GLOSSARY.md, "Challenges"): one member's attempt at a Challenge.
# Only one Active Run per member per Challenge (ux_challenge_runs_one_active).
# Starting, abandoning and progress arrive with ticket #378; until then a Run
# only locks its Challenge's rules.
class ChallengeRun < ApplicationRecord
  STATUSES = %w[active finished expired abandoned].freeze

  belongs_to :challenge, inverse_of: :runs
  belongs_to :user, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id, inverse_of: false

  validates :status, inclusion: { in: STATUSES }
end
