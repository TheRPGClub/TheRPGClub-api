# frozen_string_literal: true

# GOTM / Non-RPG GOTM nominations, votes and the round lifecycle (#172, #173).
module Voting
  # The two voting categories share one lifecycle and identically shaped
  # tables, so every per-category step iterates this map.
  CATEGORIES = {
    "gotm" => { nomination: "GotmNomination", vote: "GotmVote", entry: "GotmEntry" },
    "nr_gotm" => { nomination: "NrGotmNomination", vote: "NrGotmVote", entry: "NrGotmEntry" }
  }.freeze

  # Whether the backend runs the round lifecycle's side effects itself:
  # recording winners from the tally, creating the next round and queueing
  # the bot's posts. Off until the bot consumes voting_events; until then its
  # round-setup wizard records winners and Voting::LegacySync mirrors that.
  # Phases are derived from timestamps either way, so reads are always right.
  def self.automation_enabled?
    ENV["VOTING_AUTOMATION_ENABLED"] == "true"
  end

  def self.models_for(category)
    CATEGORIES.fetch(category.to_s).transform_values(&:constantize)
  end
end
