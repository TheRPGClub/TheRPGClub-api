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

  # A Feature Flag state other than Off, Preview or Live.
  class InvalidState < ArgumentError; end

  # The one check of a state to store: returns it as a String, or raises
  # InvalidState. FeatureFlag.change! (and through it Features::ChangeFlag)
  # uses it.
  def self.check_state!(state)
    state = state.to_s
    raise InvalidState, "state must be one of #{STATES.join(', ')}" unless STATES.include?(state)

    state
  end

  Feature = Data.define(:key, :name, :core, :coverage) do
    def core? = core
    def hideable? = !core
  end

  def self.define(key, name, core:, website: [], bot: [], posts: [])
    Feature.new(key: key, name: name, core: core,
      coverage: { website: website.freeze, bot: bot.freeze, posts: posts.freeze }.freeze)
  end
  private_class_method :define

  # `website` uses the website's own labels (sidebar items, page sections,
  # profile lists), and names the pieces of other pages each Feature removes,
  # so /settings' "where it shows up" line says more than the Feature's name.
  REGISTRY = [
    define("game_index", "Game Index", core: true,
      website: [ "Games", "Game pages" ],
      bot: [ "/gamedb", "/hltb" ]),
    define("voting_gotm", "Voting & GOTM", core: true,
      website: [ "Voting", "GOTM history", "Dashboard voting panel", "Game page ballot", "Landing page winners" ],
      bot: [ "/nominate", "/vote", "/round", "/round-history", "/gotm" ],
      posts: [ "Voting panels", "Voting results" ]),
    define("backlog", "Backlog", core: true,
      website: [ "Profile Backlog" ],
      bot: [ "/backlog" ]),
    define("collection", "Collection", core: true,
      website: [ "Profile Collection", "Collection imports" ],
      bot: [ "/collection" ]),
    define("now_playing", "Now Playing", core: true,
      website: [ "Profile Playing", "Game page Playing now" ],
      bot: [ "/now-playing", "Now playing (context menu)" ]),
    define("game_completions", "Game Completions", core: true,
      website: [ "Profile Completed", "Game page Completed by", "Completion imports" ],
      bot: [ "/game-completion", "Compare completions (context menu)" ],
      posts: [ "Completion announcements" ]),
    define("reviews", "Reviews", core: false,
      website: [ "Game page Reviews", "Profile Reviews", "Dashboard review counts" ]),
    define("achievement_hub", "Achievement Hub", core: false,
      website: [ "Achievements", "Game page Achievements", "Profile Achievements", "Linked Accounts" ],
      posts: [ "Achievement Highlights" ]),
    define("giveaways", "Giveaways", core: false,
      website: [ "Giveaways", "Donate", "Your claimed keys" ],
      bot: [ "/giveaway" ],
      posts: [ "Giveaway hub", "Giveaway claim notices" ]),
    define("journals", "Journals", core: false,
      website: [ "Game Journals", "Game page Journals", "Profile Game Journal" ],
      bot: [ "/game-journal" ]),
    define("suggestions", "Suggestions", core: false,
      website: [ "Suggestion Board" ],
      bot: [ "/suggestion" ],
      posts: [ "Suggestion posts" ]),
    # Spec #355. Registered after Feature Flags shipped, so it has no stored
    # state and starts in Preview.
    define("news_hub", "News Hub", core: false,
      website: [ "News" ],
      bot: [ "/news-import" ])
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

  # How long this process keeps the states for request-time reads.
  STATES_TTL = 5.seconds

  # Features.states, kept in this process for STATES_TTL: the feature gate
  # and the sections that embed a Feature read it on every request. A change
  # through FeatureFlag.change! forgets it in the process that made it;
  # other processes see it within STATES_TTL. Jobs read Features.state.
  def self.cached_states
    kept = @cached_states
    return kept.last if kept && Time.current - kept.first < STATES_TTL

    states.freeze.tap { |fresh| @cached_states = [ Time.current, fresh ].freeze }
  end

  def self.forget_cached_states!
    @cached_states = nil
  end

  # Whether the Feature is Off: nobody can use it and its automated activity
  # (the API's scheduled jobs it owns) is paused. Jobs skip a run while this
  # holds; work that falls due meanwhile stays due and runs once it is back on.
  def self.off?(key) = state(key) == "off"
end
