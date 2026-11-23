# frozen_string_literal: true

module DashboardPanels
  # Which Dashboard Panels a viewer can see right now: a panel whose Feature
  # the session's `features` show (Feature Flag, role and Feature
  # Preferences, through Features::Access), or one that needs no Feature.
  class Viewer
    def initialize(access)
      @access = access
    end

    def sees?(key)
      feature = DashboardPanels.fetch(key).feature
      feature.nil? || @access.shown?(feature)
    end
  end
end
