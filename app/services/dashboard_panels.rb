# frozen_string_literal: true

# Dashboard Panels (GLOSSARY.md "Dashboard Panel"; spec api#421; docs/adr/0012):
# the blocks of recent club or personal activity a member shows below the
# current issue on their own dashboard.
#
# The API owns this list. Each panel has a stable key, a scope (club activity
# or the member's own), the Feature it needs (Features::Access#shown?; none
# means everyone). A panel is "New" to a member until they open edit mode with
# it on the site (DashboardPanels::List).
# Labels, icons, layout and items are the website's.
#
# A member with no saved list follows DEFAULT. Who sees which panel is decided
# by DashboardPanels::Viewer; a member's saved list by DashboardPanels::List.
module DashboardPanels
  # The club default, in order, for members who never changed their list.
  DEFAULT = %w[news now_playing_club releases achievements_club challenges_club].freeze

  # `scope` is "club" or "mine"; `feature` the Feature the panel needs, nil
  # for none.
  Panel = Data.define(:key, :scope, :feature)

  def self.panel(key, scope, feature) = Panel.new(key: key, scope: scope, feature: feature)

  PANELS = [
    panel("news", "club", "news_hub"),
    panel("now_playing_club", "club", "now_playing"),
    panel("releases", "club", "release_calendar"),
    panel("achievements_club", "club", "achievement_hub"),
    panel("challenges_club", "club", "challenges"),
    panel("now_playing_mine", "mine", "now_playing"),
    panel("achievements_mine", "mine", "achievement_hub"),
    panel("challenge_runs_mine", "mine", "challenges"),
    panel("completions_club", "club", "game_completions"),
    panel("completions_mine", "mine", "game_completions"),
    panel("backlog_pick", "mine", "backlog"),
    panel("reviews", "club", "reviews"),
    panel("journals", "club", "journals"),
    panel("giveaways", "club", "giveaways"),
    panel("suggestions", "club", "suggestions"),
    panel("codex", "club", "club_codex"),
    panel("birthdays", "club", nil)
  ].freeze

  BY_KEY = PANELS.index_by(&:key).freeze

  # The panels the site launched with. A member who never opened edit mode has
  # seen these and nothing else, so none is New at launch and every panel
  # added later is. Never add a key here: a later panel stays out so it is New.
  LAUNCH_KEYS = %w[
    news now_playing_club releases achievements_club challenges_club now_playing_mine achievements_mine
    challenge_runs_mine completions_club completions_mine backlog_pick reviews journals giveaways
    suggestions codex birthdays
  ].freeze

  def self.all = BY_KEY.values

  def self.keys = BY_KEY.keys

  def self.known?(key) = key.is_a?(String) && BY_KEY.key?(key)

  def self.fetch(key) = BY_KEY.fetch(key)
end
