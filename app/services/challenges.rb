# frozen_string_literal: true

# Challenges (GLOSSARY.md, "Challenges"; spec #376). The API owns every rule:
# who may create and change a Challenge (Challenges::Actor), its schedule
# (Challenges::Schedule), its Challenge Format's settings
# (Challenges::Formats), the writes (Challenges::Form) and its announcements
# (Challenges::Announcements).
module Challenges
  # Every Challenge date is in the club's time zone, the one voting uses.
  TIME_ZONE = Voting::Schedule::TIME_ZONE

  # A request the rules refuse: rendered 422 `{ error: "invalid_challenge",
  # message: }`.
  class Invalid < StandardError; end

  # A change to a locked rule of a Challenge that has Runs: rendered 409
  # `{ error: "rules_locked", message:, fields: }`.
  class RulesLocked < StandardError
    attr_reader :fields

    def initialize(fields)
      @fields = fields
      super("The rules are locked because this Challenge has Runs: #{fields.join(', ')} can no longer change. " \
            "Name, description and end date stay editable.")
    end
  end

  # The club's date today.
  def self.today(now = Time.current)
    now.in_time_zone(TIME_ZONE).to_date
  end
end
