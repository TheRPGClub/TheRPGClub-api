# frozen_string_literal: true

module Challenges
  # The Challenge Formats (GLOSSARY.md, "Challenge Format") and the settings
  # each keeps. A Challenge's request body carries its Format's settings
  # under the Format's key (`"pool": { ... }`), and its response shows them
  # under the same key.
  #
  # Each Format is a module answering:
  #   load(challenge)                    its stored settings
  #   parse(input, base:)                settings from a request's object,
  #                                      over `base` (the stored ones on edit);
  #                                      raises Challenges::Invalid
  #   errors(settings)                   why they are not valid ([] if they are)
  #   apply!(challenge, settings)        writes them (inside the save's transaction)
  #   rules(settings)                    a comparable value: a change to it
  #                                      is a rule change, locked once Runs exist
  #   as_json(challenge, settings, detail:)  the response object
  #
  # and, for Run progress (Challenges::Progress, which describes them):
  #   count(run, plays)                  the games the Run counts now
  #   summary(run, entries)              In Progress, Cleared, target, goal
  #                                      (and Caught Up, for Slots)
  #
  # and, for starting a Run (Challenges::Runs.start!):
  #   run_attributes(challenge, user_id, today:)  what the new Run copies;
  #                                      raises Challenges::RunRefused
  #   notices(run)                       what the member is told on start
  #
  # Assignment (Secret Santa) runs in Editions (Challenges::Editions): its
  # Runs come from the draw, so it refuses run_attributes.
  module Formats
    REGISTRY = { "pool" => Formats::Pool, "slots" => Formats::Slots, "assignment" => Formats::Assignment }.freeze

    def self.supported = REGISTRY.keys

    # The Format module for `key`; raises Challenges::Invalid for a Format
    # that does not exist.
    def self.fetch(key)
      REGISTRY.fetch(key.to_s) { raise Invalid, "challenge_format must be one of #{supported.join(', ')}" }
    end
  end
end
