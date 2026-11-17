# frozen_string_literal: true

# A member's Finish of a Seasonal Challenge in one Season was announced
# (Challenges::Progress): one row per (Challenge, member, Season), kept when
# the Run is deleted, so a new Run in the same Season is never announced
# again.
class ChallengeFinishAnnouncement < ApplicationRecord
  self.primary_key = %i[challenge_id user_id season_starts_on]

  # Records the Finish of the Seasonal `run`; whether it is the first in its
  # Season (and so should be announced).
  def self.first?(run)
    insert_all([ { challenge_id: run.challenge_id, user_id: run.user_id, season_starts_on: run.season_starts_on } ],
      returning: %i[challenge_id]).rows.any?
  end
end
