# frozen_string_literal: true

# The club's Features (GLOSSARY.md, "Features"; spec #347; docs/adr/0005).
#
# The list of Features is defined here, in code; only each Feature Flag's
# state is stored (FeatureFlag). Adding a Feature therefore means an API
# release, and a new Feature starts in Preview because it has no stored state
# until staff set one.
#
# Each Feature names what it covers, so staff know what a flag change
# switches: its pages and sections on the website, its bot commands, and the
# automated posts it makes. Core Features cannot be hidden by a Feature
# Preference; every other Feature is hideable.
#
# Not Features, never flagged or hidden: the dashboard, members and profiles,
# sign-in, the staff desk, and the bot's utility, mod and admin commands.
#
# Who may use or see a Feature is decided by Features::Access.
module Features
  STATES = %w[off preview live].freeze
  DEFAULT_STATE = "preview"

  Feature = Data.define(:key, :name, :core, :coverage) do
    def core? = core
    def hideable? = !core
  end

  def self.define(key, name, core:, website: [], bot: [], posts: [])
    Feature.new(key: key, name: name, core: core,
      coverage: { website: website.freeze, bot: bot.freeze, posts: posts.freeze }.freeze)
  end
  private_class_method :define

  REGISTRY = [
    define("game_index", "Game Index", core: true,
      website: [ "Games index", "Game pages" ],
      bot: [ "/gamedb", "/hltb" ]),
    define("voting_gotm", "Voting & GOTM", core: true,
      website: [ "Voting", "GOTM history", "Landing page winners" ],
      bot: [ "/nominate", "/vote", "/round", "/round-history", "/gotm" ],
      posts: [ "Voting panels", "Voting results" ]),
    define("backlog", "Backlog", core: true,
      website: [ "Backlog" ],
      bot: [ "/backlog" ]),
    define("collection", "Collection", core: true,
      website: [ "Collection", "Collection imports" ],
      bot: [ "/collection" ]),
    define("now_playing", "Now Playing", core: true,
      website: [ "Now Playing" ],
      bot: [ "/now-playing", "Now playing (context menu)" ]),
    define("game_completions", "Game Completions", core: true,
      website: [ "Completions", "Completion imports" ],
      bot: [ "/game-completion", "Compare completions (context menu)" ],
      posts: [ "Completion announcements" ]),
    define("reviews", "Reviews", core: false,
      website: [ "Game page Reviews tab", "Profile reviews" ]),
    define("achievement_hub", "Achievement Hub", core: false,
      website: [ "Achievements", "Profile Achievements" ],
      posts: [ "Achievement Highlights" ]),
    define("giveaways", "Giveaways", core: false,
      website: [ "Giveaways", "Dashboard Giveaways panel" ],
      bot: [ "/giveaway" ],
      posts: [ "Giveaway hub", "Giveaway claim notices" ]),
    define("journals", "Journals", core: false,
      website: [ "Journals", "Profile Journal" ],
      bot: [ "/game-journal" ]),
    define("suggestions", "Suggestions", core: false,
      website: [ "Suggestions" ],
      bot: [ "/suggestion" ],
      posts: [ "Suggestion posts" ])
  ].freeze

  BY_KEY = REGISTRY.index_by(&:key).freeze

  def self.all = REGISTRY

  def self.keys = BY_KEY.keys

  def self.find(key)
    BY_KEY[key.to_s]
  end

  def self.fetch(key)
    find(key) || raise(KeyError, "unknown Feature: #{key}")
  end

  def self.known?(key) = BY_KEY.key?(key.to_s)

  # Every registered Feature's Feature Flag state, keyed by Feature key. A key
  # with no stored state reads as Preview.
  def self.states
    stored = FeatureFlag.where(key: keys).pluck(:key, :state).to_h
    keys.index_with { |key| stored.fetch(key, DEFAULT_STATE) }
  end

  def self.state(key)
    fetch(key)
    FeatureFlag.where(key: key.to_s).pick(:state) || DEFAULT_STATE
  end
end
