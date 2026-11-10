# frozen_string_literal: true

module Features
  # The one place that decides who can use and who is shown each Feature
  # (spec #347, docs/adr/0005). Endpoints, the session and the bot lookup all
  # ask this module; no client decides for itself.
  #
  # For a viewer and a Feature it answers:
  #   can_use?  the Feature Flag lets this viewer use the Feature: everyone
  #             when Live, staff only in Preview, nobody when Off.
  #   shown?    the viewer can use it and it is not hidden from their view.
  #   hideable? a member may hide it with a Feature Preference (not Core).
  #   preview?  the viewer can use it only because they are staff.
  #
  # `staff` means Admin or Superadmin as the existing staff gates define them
  # (StaffGates#admin_or_above?); callers pass that answer in.
  #
  # The viewer's Feature Preferences (`hidden`, the hideable Feature keys they
  # hid) and the staff show-Preview setting (`show_preview`, on by default)
  # narrow `shown?` only. They never change `can_use?`, so a preference never
  # blocks an endpoint or a direct link.
  #
  #   access = Features::Access.new(staff: admin_or_above?)
  #   access.can_use?(:reviews)
  #   access.session_features # => [{ key:, name:, state:, hideable:, shown:, preview: }, ...]
  class Access
    # Access for a signed-in viewer: `staff` as the caller decided it, narrowed
    # by the stored member's Feature Preferences and show-Preview setting
    # (`user` is nil for the service token or a member with no record).
    def self.for_viewer(user, staff:, states: Features.states)
      new(staff: staff, states: states,
        hidden: user ? MemberFeaturePreference.hidden_keys(user.user_id) : [],
        show_preview: user ? user.show_preview_features : true)
    end

    def initialize(staff:, states: Features.states, hidden: [], show_preview: true)
      @staff = staff ? true : false
      @states = states
      @hidden = hidden.map(&:to_s)
      @show_preview = show_preview ? true : false
    end

    def staff? = @staff

    def state(key)
      @states.fetch(Features.fetch(key).key)
    end

    def can_use?(key)
      case state(key)
      when "live" then true
      when "preview" then staff?
      else false
      end
    end

    # Can use it, has not hidden it, and, for a staff member who turned
    # "show Preview features" off, it is not a Preview Feature.
    def shown?(key)
      can_use?(key) && !hidden?(key) && !(preview?(key) && !@show_preview)
    end

    # The viewer hid this Feature with a Feature Preference. Core Features are
    # never hidden.
    def hidden?(key)
      hideable?(key) && @hidden.include?(Features.fetch(key).key)
    end

    def hideable?(key)
      Features.fetch(key).hideable?
    end

    def preview?(key)
      staff? && state(key) == "preview"
    end

    # The session's `features` list, in registry order. Staff get every
    # Feature in every state; anyone else gets only Live Features, so a
    # Preview or Off Feature never reaches a member's session.
    def session_features
      Features.all.filter_map do |feature|
        next unless staff? || state(feature.key) == "live"

        {
          key: feature.key,
          name: feature.name,
          state: state(feature.key),
          hideable: feature.hideable?,
          shown: shown?(feature.key),
          preview: preview?(feature.key)
        }
      end
    end

    # The Features the viewer may hide on their settings page, in registry
    # order: every hideable Feature they can use (Live, plus Preview for
    # staff, badged with `preview`), whether they hid it, and where it shows
    # up on the website.
    def preference_features
      Features.all.filter_map do |feature|
        next unless feature.hideable? && can_use?(feature.key)

        {
          key: feature.key,
          name: feature.name,
          state: state(feature.key),
          preview: preview?(feature.key),
          hidden: hidden?(feature.key),
          website: feature.coverage[:website]
        }
      end
    end
  end
end
