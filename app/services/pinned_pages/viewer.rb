# frozen_string_literal: true

module PinnedPages
  # Which pinnable pages a viewer can see right now: a Feature page when the
  # session's `features` show it (Feature Flag, role and Feature Preferences,
  # through Features::Access), a staff page when the viewer holds its tier.
  #
  # Tiers come from the request's StaffGates answers, as the controller has
  # them: `moderator` (moderator_or_above?), `admin` (admin_or_above?) and
  # `superadmin` (superadmin?).
  class Viewer
    def initialize(access:, moderator:, admin:, superadmin:)
      @access = access
      @tiers = { moderator: moderator, admin: admin, superadmin: superadmin }
    end

    def sees?(key)
      page = PinnedPages.fetch(key)
      return @tiers.fetch(page.staff) ? true : false if page.staff
      return @access.shown?(page.feature) if page.feature

      true
    end
  end
end
