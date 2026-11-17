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
  # Slots (#381) and Assignment (#383) register here when they are built.
  module Formats
    REGISTRY = { "pool" => Formats::Pool }.freeze

    def self.supported = REGISTRY.keys

    # The Format module for `key`; raises Challenges::Invalid for a Format
    # that is not available yet or does not exist.
    def self.fetch(key)
      REGISTRY.fetch(key.to_s) do
        if Challenge::FORMATS.include?(key.to_s)
          raise Invalid, "The #{key} Challenge Format is not available yet"
        end

        raise Invalid, "challenge_format must be one of #{supported.join(', ')}"
      end
    end
  end
end
