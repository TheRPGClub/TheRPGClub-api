# frozen_string_literal: true

# Challenges (GLOSSARY.md, "Challenges"; spec #376). The API owns every rule:
# who may create and change a Challenge (Challenges::Actor), its schedule
# (Challenges::Schedule), its Challenge Format's settings
# (Challenges::Formats), the writes (Challenges::Form), Runs (Challenges::Runs)
# and their progress (Challenges::Progress), its announcements
# (Challenges::Announcements) and DMs (Challenges::DirectMessages), and its
# timed side (Challenges::Lifecycle).
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

  # A Run request the rules refuse: rendered with `status` as
  # `{ error: code, message:, **details }`.
  class RunRefused < StandardError
    attr_reader :code, :status, :details

    def initialize(code, message, status: :conflict, **details)
      @code = code
      @status = status
      @details = details
      super(message)
    end
  end

  # Brings the member's Runs up to date with their Game Completions and Now
  # Playing (Challenges::Progress) and queues the announcements for the Runs
  # that changed, in one transaction. Called after every commit that writes
  # a Game Completion or Now Playing entry (Challenges::CountsTowardRuns).
  def self.refresh_runs!(user_id)
    ChallengeRun.transaction do
      Progress.refresh(user_id).each { |change| Announcements.run_changed!(change) }
    end
  end

  # The club's date today.
  def self.today(now = Time.current)
    now.in_time_zone(TIME_ZONE).to_date
  end
end
