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
  # (StaffGates#admin_or_above?); callers pass that answer in. Feature
  # Preferences and the staff show-Preview setting are not stored yet; when
  # they are, they narrow `shown?` and never `can_use?`.
  #
  #   access = Features::Access.new(staff: admin_or_above?)
  #   access.can_use?(:reviews)
  #   access.session_features # => [{ key:, name:, state:, hideable:, shown:, preview: }, ...]
  class Access
    # Access for a stored member (nil for a Discord user with no record), with
    # staff read from their role flags: Admin, or Superadmin by the dev role.
    # For callers acting for a Discord user without their session, i.e. the bot.
    def self.for_member(user, states: Features.states)
      new(staff: user&.admin_or_above?, states: states)
    end

    def initialize(staff:, states: Features.states)
      @staff = staff ? true : false
      @states = states
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

    def shown?(key)
      can_use?(key)
    end

    def hideable?(key)
      Features.fetch(key).hideable?
    end

    def preview?(key)
      staff? && state(key) == "preview"
    end

    # The bot's per-user lookup: every Feature in registry order, whatever its
    # state, so the bot's gate can tell "not available" from "Preview".
    def lookup_features
      Features.all.map do |feature|
        {
          key: feature.key,
          name: feature.name,
          state: state(feature.key),
          can_use: can_use?(feature.key),
          preview: preview?(feature.key)
        }
      end
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
  end
end
