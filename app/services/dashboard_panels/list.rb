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

    # Marks every panel on the site as seen (the member opened edit mode).
    def seen!
      @user ||= RpgClubUser.create_or_find_by!(user_id: @user_id)
      @user.update!(dashboard_panels_seen_keys: DashboardPanels.keys)
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
