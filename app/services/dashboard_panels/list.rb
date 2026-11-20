# frozen_string_literal: true

module DashboardPanels
  # A member's Dashboard Panels (Members::OrderedList): their saved list in
  # order, or the club default until they first save one
  # (`dashboard_panels_customised` on the member), and which panels are new to
  # them. Panels they can't see right now (a Feature Off or hidden by a
  # Feature Preference) are kept on save, so they return when the Feature does.
  class List < Members::OrderedList
    # Every panel the member can see right now, shown or not, in the club's
    # order, with whether it is new to them.
    def catalogue
      DashboardPanels.all.select { |panel| @viewer.sees?(panel.key) }.map do |panel|
        { key: panel.key, scope: panel.scope, new: new?(panel) }
      end
    end

    # Marks panels as seen (the member opened edit mode): `shown`, the keys
    # the website listed there, or every panel on the site when nil. Panels
    # the website didn't list yet (the API deploys first) stay new. Returns
    # why it can't, changing nothing, or nil once marked.
    def seen!(shown = nil)
      return "panels must be a list of panel keys" unless shown.nil? || shown.is_a?(Array)

      @user ||= RpgClubUser.create_or_find_by!(user_id: @user_id)
      keys = shown.nil? ? DashboardPanels.keys : (seen_keys | shown).select { |key| DashboardPanels.known?(key) }
      @user.update!(dashboard_panels_seen_keys: keys)
      nil
    end

    private

    def catalog = DashboardPanels
    def model = MemberDashboardPanel
    def key_column = :panel_key
    def customised_column = :dashboard_panels_customised
    def list_name = "panels"
    def key_name = "panel"
    def chosen_word = "shown"

    # A panel is new until the member opens edit mode while it is on the site,
    # however long after it was written it deploys. A member who never opened
    # edit mode (or whose `seen` call failed) has seen the launch panels only.
    def new?(panel) = !seen_keys.include?(panel.key)

    def seen_keys = @user&.dashboard_panels_seen_keys || DashboardPanels::LAUNCH_KEYS
  end
end
