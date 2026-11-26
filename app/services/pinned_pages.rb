# frozen_string_literal: true

# Pinned Pages (GLOSSARY.md "Pinned Page"; spec api#416; docs/adr/0012): the
# website pages a member can pin to the top of their own sidebar.
#
# The API owns this list. Each page has a stable key and what a viewer needs
# to see it: a Feature (Features::Access#shown?) or a staff tier. The website
# maps keys to routes, icons, labels and groups. Dashboard, Settings and the
# member's own profile have fixed places and are not pinnable.
#
# A member with no saved list follows DEFAULT. Who sees which page is decided
# by PinnedPages::Viewer; a member's saved list by PinnedPages::List.
module PinnedPages
  LIMIT = 6

  # The club default, for members who never changed their list.
  DEFAULT = %w[voting games members news].freeze

  # `feature` is the Feature the page needs, `staff` the staff tier
  # (:moderator, :admin or :superadmin); neither means everyone.
  Page = Data.define(:key, :feature, :staff)

  def self.page(key, feature: nil, staff: nil) = Page.new(key: key, feature: feature, staff: staff)

  # Staff tiers mirror the website's lib/staff.ts nav sections.
  PAGES = [
    page("voting", feature: "voting_gotm"),
    page("gotm_history", feature: "voting_gotm"),
    page("goty", feature: "goty_vote"),
    page("challenges", feature: "challenges"),
    page("games", feature: "game_index"),
    page("franchises"),
    page("reviews", feature: "reviews"),
    page("releases", feature: "release_calendar"),
    page("achievements", feature: "achievement_hub"),
    page("journals", feature: "journals"),
    page("members"),
    page("news", feature: "news_hub"),
    page("codex", feature: "club_codex"),
    page("lists", feature: "game_lists"),
    page("giveaways", feature: "giveaways"),
    page("feedback", feature: "feedback"),
    page("staff_desk", staff: :moderator),
    page("voting_console", staff: :admin),
    page("synonyms", staff: :admin),
    page("live_events", staff: :moderator),
    page("public_reminders", staff: :admin),
    page("feedback_review", staff: :superadmin)
  ].freeze

  BY_KEY = PAGES.index_by(&:key).freeze

  def self.keys = BY_KEY.keys

  def self.known?(key) = key.is_a?(String) && BY_KEY.key?(key)

  def self.fetch(key) = BY_KEY.fetch(key)
end
