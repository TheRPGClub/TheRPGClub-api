# frozen_string_literal: true

module Challenges
  # Creates or edits a Challenge from a request's `data` (spec #376):
  #
  #   name, description
  #   challenge_format   "pool", "slots" or "assignment"; set on create
  #   schedule           "always_open" or "seasonal"
  #   ends_on            an Always Open Challenge's last day (YYYY-MM-DD), or null
  #   season             a Seasonal Challenge's { start: "MM-DD", end: "MM-DD" }
  #   pool               the Pool's settings (Challenges::Formats::Pool)
  #   slots              the slot range and Counts past play
  #                      (Challenges::Formats::Slots)
  #   assignment         the Edition calendar (Challenges::Formats::Assignment)
  #   tint               a curated tint's name, { fill, hi }, or null for the
  #                      Challenge's curated one (Challenges::Tint); not a rule,
  #                      so it stays editable
  #
  # On edit, only the keys given change. Once the Challenge has any Run its
  # rules (Format, schedule, Season and the Format's locked settings: all of
  # Slots and Assignment, none of a Pool) are locked: a change to them raises
  # Challenges::RulesLocked, while sending them unchanged is fine. Name, description and end date stay editable, except
  # that an Always Open Challenge that reached its end date (`ended_at`, set
  # by the lifecycle job) is Closed for good, so its schedule and end date no
  # longer change. Raises Challenges::Invalid for anything the rules refuse.
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
      Challenge.transaction do
        # Locked as a Run starting locks it (Challenges::Runs.start!), so
        # the rules lock below sees a first Run that is starting now.
        Challenge.where(id: challenge.id).lock.ids if challenge.persisted?
        locked = challenge.persisted? && challenge.runs?
        before = rules if locked
        assign_text
        assign_tint
        assign_format
        assign_schedule
        refuse_reopening if challenge.ended_at
        refuse_linking
        format = Formats.fetch(challenge.challenge_format)
        before_settings = stored_settings(format)
        settings = format.parse(@data[format::KEY], base: before_settings)
        refuse_invalid(format.errors(settings, challenge))
        check_unlocked(before, rules(format, settings)) if locked

        challenge.save!
        format.apply!(challenge, settings)
        edited(format, before_settings, settings) if locked
      end
      challenge
    end

    private

    attr_reader :challenge

    def assign_text
      TEXT_KEYS.each { |key| challenge.public_send(:"#{key}=", @data[key].to_s) if @data.key?(key) }
    end

    def assign_tint
      challenge.tint = Tint.parse(@data["tint"]) if @data.key?("tint")
    end

    def assign_format
      if challenge.new_record?
        raise Invalid, "challenge_format is required" unless @data.key?("challenge_format")
      elsif !@data.key?("challenge_format")
        return
      end

      challenge.challenge_format = @data["challenge_format"].to_s
      Formats.fetch(challenge.challenge_format)
      # Counts past play is a Slots setting, which a switch to Slots gives
      # in full (stored_settings), and which no other Format keeps.
      challenge.counts_past_play = false if challenge.challenge_format_changed?
      # Only a Pool is fed by a linked Game List.
      challenge.pool_game_list_id = nil if challenge.challenge_format != Formats::Pool::KEY
    end

    # A Game List is linked only on create (Challenges::ListLink), which
    # takes `pool.game_list_id` out of the data first.
    def refuse_linking
      pool = @data[Formats::Pool::KEY]
      return unless pool.is_a?(Hash) && pool.key?("game_list_id")

      raise Invalid, "pool game_list_id can only be set when the Challenge is created"
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

    ENDED = "This Challenge reached its end date and is Closed for good, so its schedule and end date can no " \
            "longer change."

    def refuse_reopening
      raise Invalid, ENDED if challenge.will_save_change_to_schedule? || challenge.will_save_change_to_ends_on?
    end

    # The Format's stored settings, which an edit changes only where it says;
    # none on create or when the edit switches to another Format, which then
    # needs its settings in full.
    def stored_settings(format)
      return nil if challenge.new_record? || challenge.challenge_format_changed?

      format.load(challenge)
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

    # A Format that follows up on edits to a Challenge with Runs (a Pool
    # refreshes them and DMs a grown goal) answers edited!.
    def edited(format, before, after)
      format.edited!(challenge, before, after) if before && format.respond_to?(:edited!)
    end

    def check_unlocked(before, after)
      changed = after.keys.reject { |key| before[key] == after[key] }
      raise RulesLocked, changed.map { |key| RULE_FIELDS.fetch(key, key) }.uniq if changed.any?
    end
  end
end
