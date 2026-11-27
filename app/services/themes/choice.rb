# frozen_string_literal: true

module Themes
  # A Member's Theme as their Feature access allows it (spec api#523, ticket
  # api#524; docs/adr/0017).
  #
  # Which Themes the Member may choose follows the Themes Feature:
  #   Off      only the default, for everyone.
  #   Preview  every Theme for staff; only the default for anyone else.
  #   Live     every Released Theme for everyone; every Theme for staff.
  # The default is always available. As for the session's other fields, a
  # staff member who turned "show Preview features" off is not offered the
  # Themes Feature while it is in Preview (Features::Access#shown?; Themes is
  # Core, so no Feature Preference hides it otherwise).
  #
  # `chosen` is the Member's stored Theme (RpgClubUser#theme, nil for none).
  # A stored Theme that is unavailable, or a key the API no longer knows, is
  # kept but resolves to the default, so it comes back when it is available.
  # The payload names it only when it leaks nothing: an unreleased Theme
  # stored by a viewer who is not staff is reported as no choice.
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
      return false unless @access && Themes.known?(key) && @access.shown?(FEATURE)

      Themes.fetch(key).released? || @access.staff?
    end

    # The key of the Theme the Member sees right now.
    def current
      chosen && available?(chosen) ? chosen : DEFAULT
    end

    # The Themes for the picker, in list order: every Theme the Member may
    # choose, plus their stored Theme when it is known but unavailable and
    # reportable, so the picker can show it as unavailable.
    def list
      Themes.all.filter_map do |theme|
        available = available?(theme.key)
        next unless available || (theme.key == chosen && reportable?)

        { key: theme.key, name: theme.name, released: theme.released?, available: available }
      end
    end

    # The session's theme fields; PUT /api/v1/me/theme returns the same.
    def document
      { theme: current, themes: { chosen: reportable? ? chosen : nil, list: list } }
    end

    private

    # Whether the payload may name the stored Theme: anything but an
    # unreleased Theme stored by a viewer who is not staff, whose name would
    # leak it. Unknown keys name nothing and are reported as stored.
    def reportable?
      return true unless chosen && Themes.known?(chosen)

      Themes.fetch(chosen).released? || @access&.staff? || false
    end
  end
end
