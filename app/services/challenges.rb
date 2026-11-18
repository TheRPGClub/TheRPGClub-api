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

  # A sign-up or withdrawal for an Edition the rules refuse
  # (Challenges::Editions): rendered like a RunRefused.
  class SignupRefused < RunRefused; end

  # Brings the member's Runs up to date with their Game Completions and Now
  # Playing (Challenges::Progress) and queues the announcements for the Runs
  # that changed, in one transaction. Called after every commit that writes
  # a Game Completion or Now Playing entry (Challenges::CountsTowardRuns).
  def self.refresh_runs!(user_id)
    ChallengeRun.transaction do
      Progress.refresh(user_id).each { |change| Announcements.run_changed!(change) }
    end
  end

  # A member as Challenge JSON and bot payloads serve them: their names, the
  # Discord avatar hash stored at their last login (null if unknown; with the
  # user id it makes a Discord CDN URL), and the path of the avatar image the
  # bot stores (GET /api/v1/users/{id}/avatar, which 404s when it has none).
  def self.member(user)
    { user_id: user.user_id, username: user.username, global_name: user.global_name,
      discord_avatar: user.discord_avatar, avatar_url: "/api/v1/users/#{user.user_id}/avatar" }
  end

  # The name a member goes by in job summaries: their Discord display name,
  # else their username, else their id.
  def self.display_name(user) = user.global_name.presence || user.username.presence || user.user_id

  # The club's date today.
  def self.today(now = Time.current)
    now.in_time_zone(TIME_ZONE).to_date
  end
end
