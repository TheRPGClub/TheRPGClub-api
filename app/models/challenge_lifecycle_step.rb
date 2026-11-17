# frozen_string_literal: true

# A timed step the Challenges lifecycle job has taken for a Challenge, by the
# club date it was due on (`occurs_on`). One per Challenge, step and date
# (ux_challenge_lifecycle_steps_once), so a step is taken once however often
# the job runs. Written only by Challenges::Lifecycle.once!.
class ChallengeLifecycleStep < ApplicationRecord
  belongs_to :challenge, inverse_of: false
end
