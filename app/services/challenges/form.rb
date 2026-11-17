# frozen_string_literal: true

module Challenges
  # Creates or edits a Challenge from a request's `data` (spec #376):
  #
  #   name, description
  #   challenge_format   "pool" (Slots and Assignment arrive later); set on create
  #   schedule           "always_open" or "seasonal"
  #   ends_on            an Always Open Challenge's last day (YYYY-MM-DD), or null
  #   season             a Seasonal Challenge's { start: "MM-DD", end: "MM-DD" }
  #   pool               the Pool's settings (Challenges::Formats::Pool)
  #
  # On edit, only the keys given change. Once the Challenge has any Run its
  # rules (Format, schedule, Season and the Format's settings) are locked: a
  # change to them raises Challenges::RulesLocked, while sending them
  # unchanged is fine. Name, description and end date stay editable. Raises
  # Challenges::Invalid for anything the rules refuse.
  class Form
    TEXT_KEYS = %w[name description].freeze
    # The public name of each locked rule, by the column it is stored in.
    RULE_FIELDS = {
      "challenge_format" => "challenge_format", "schedule" => "schedule",
      "season_start_month" => "season", "season_start_day" => "season",
      "season_end_month" => "season", "season_end_day" => "season"
    }.freeze

    def initialize(challenge, data)
      @challenge = challenge
      @data = data.to_h.stringify_keys
    end

    def save!
      locked = challenge.persisted? && challenge.runs?
      before = rules if locked
      assign_text
      assign_format
      assign_schedule
      format = Formats.fetch(challenge.challenge_format)
      settings = format.parse(@data[format::KEY], base: challenge.persisted? ? format.load(challenge) : nil)
      refuse_invalid(format.errors(settings))
      check_unlocked(before, rules(format, settings)) if locked

      Challenge.transaction do
        challenge.save!
        format.apply!(challenge, settings)
      end
      challenge
    end

    private

    attr_reader :challenge

    def assign_text
      TEXT_KEYS.each { |key| challenge.public_send(:"#{key}=", @data[key].to_s) if @data.key?(key) }
    end

    def assign_format
      if challenge.new_record?
        raise Invalid, "challenge_format is required" unless @data.key?("challenge_format")
      elsif !@data.key?("challenge_format")
        return
      end

      challenge.challenge_format = @data["challenge_format"].to_s
      Formats.fetch(challenge.challenge_format)
    end

    def assign_schedule
      raise Invalid, "schedule is required" if challenge.new_record? && !@data.key?("schedule")

      challenge.schedule = @data["schedule"].to_s if @data.key?("schedule")
      if challenge.seasonal?
        raise Invalid, "ends_on is only for Always Open Challenges" if @data["ends_on"].present?

        challenge.ends_on = nil
        challenge.assign_attributes(Schedule.season_columns(@data["season"])) if @data.key?("season")
      else
        raise Invalid, "season is only for Seasonal Challenges" if @data["season"].present?

        challenge.assign_attributes(season_start_month: nil, season_start_day: nil, season_end_month: nil,
          season_end_day: nil)
        challenge.ends_on = parse_date(@data["ends_on"]) if @data.key?("ends_on")
      end
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Invalid, "ends_on must be a date as YYYY-MM-DD"
    end

    def refuse_invalid(format_errors)
      challenge.validate
      messages = challenge.errors.full_messages + format_errors
      raise Invalid, messages.join(". ") if messages.any?
    end

    # The Challenge's rules as stored, or as they would be with `settings`.
    def rules(format = nil, settings = nil)
      if format.nil?
        persisted = Challenge.find(challenge.id)
        format = persisted.format_rules
        return persisted.attributes.slice(*RULE_FIELDS.keys).merge(format::KEY => format.rules(format.load(persisted)))
      end

      challenge.attributes.slice(*RULE_FIELDS.keys).merge(format::KEY => format.rules(settings))
    end

    def check_unlocked(before, after)
      changed = after.keys.reject { |key| before[key] == after[key] }
      raise RulesLocked, changed.map { |key| RULE_FIELDS.fetch(key, key) }.uniq if changed.any?
    end
  end
end
