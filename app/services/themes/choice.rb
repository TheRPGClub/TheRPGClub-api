# frozen_string_literal: true

module Themes
  # A Member's Theme as their Feature access allows it (spec api#523, ticket
  # api#524; docs/adr/0017).
  #
  # Which Themes the Member may choose follows the Themes Feature:
  #   Off      only the default, for everyone.
  #   Preview  every Theme for staff; only the default for anyone else.
  #   Live     every Released Theme for everyone; every Theme for staff.
  # The default is always available.
  #
  # `chosen` is the Member's stored Theme (RpgClubUser#theme, nil for none).
  # A stored Theme that is unavailable, or a key the API no longer knows, is
  # kept but resolves to the default, so it comes back when it is available.
  #
  #   choice = Themes::Choice.new(access, user&.theme)
  #   choice.current  # => "monthly-issue"
  #   choice.document # => { theme:, themes: { chosen:, list: [...] } }
  class Choice
    FEATURE = :themes

    attr_reader :chosen

    # Only the default, chosen by nobody: for a viewer who is not a Member,
    # such as the bot's service token.
    def self.default = new(nil, nil)

    # `access` is the viewer's Features::Access (nil allows only the default).
    def initialize(access, chosen)
      @access = access
      @chosen = chosen.presence
    end

    def available?(key)
      return true if key == DEFAULT
      return false unless @access && Themes.known?(key) && @access.can_use?(FEATURE)

      Themes.fetch(key).released? || @access.staff?
    end

    # The key of the Theme the Member sees right now.
    def current
      chosen && available?(chosen) ? chosen : DEFAULT
    end

    # The Themes for the picker, in list order: every Theme the Member may
    # choose, plus their stored Theme when it is known but unavailable, so
    # the picker can show it as unavailable. An unreleased Theme never
    # reaches a Member who may not choose it otherwise.
    def list
      Themes.all.filter_map do |theme|
        available = available?(theme.key)
        next unless available || theme.key == chosen

        { key: theme.key, name: theme.name, released: theme.released?, available: available }
      end
    end

    # The session's theme fields; PUT /api/v1/me/theme returns the same.
    def document
      { theme: current, themes: { chosen: chosen, list: list } }
    end
  end
end
