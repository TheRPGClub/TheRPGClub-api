# frozen_string_literal: true

module DashboardPanels
  # A member's Dashboard Panels: their saved list in order, or the club
  # default until they first save one (`dashboard_panels_customised` on the
  # member), and which panels are new to them.
  #
  # Reads give only the panels the member can see right now. A save replaces
  # the list the member sees but keeps the panels they can't see (a Feature
  # Off or hidden by a Feature Preference), after the saved ones and in their
  # existing order, so they return when the Feature does.
  #
  # Saved keys the API no longer knows (a removed panel) are ignored on read
  # and dropped on the member's next save (docs/adr/0012).
  class List
    # `user` is the member's record, nil when they have none yet.
    def initialize(user_id, viewer, user)
      @user_id = user_id
      @viewer = viewer
      @user = user
    end

    # Whether the member saved their own list, rather than following DEFAULT.
    def customised? = @user&.dashboard_panels_customised || false

    # Every known key in the member's list, seen or not.
    def keys
      @keys ||= if customised?
        MemberDashboardPanel.where(user_id: @user_id).order(:position).pluck(:panel_key)
          .select { |key| DashboardPanels.known?(key) }
      else
        DEFAULT.dup
      end
    end

    # The panels the member shows and can see right now, in their order.
    def visible = keys.select { |key| @viewer.sees?(key) }

    # Every panel the member can see right now, shown or not, in the club's
    # order, with whether it is new to them.
    def catalogue
      DashboardPanels.all.select { |panel| @viewer.sees?(panel.key) }.map do |panel|
        { key: panel.key, scope: panel.scope, new: new?(panel) }
      end
    end

    # Saves `panels` (the list the member sees, in order) plus the kept hidden
    # panels as the member's whole list. Returns why it can't, changing
    # nothing, or nil once saved.
    #
    # The member's row is locked first and the list read under it, so two
    # saves at once run one after the other.
    def save(panels)
      error = shape_error(panels)
      return error if error

      RpgClubUser.transaction do
        lock_member
        write(panels + (hidden - panels))
      end
      nil
    end

    # Drops the member's saved list, so they follow DEFAULT again, including
    # later changes to it.
    def reset!
      RpgClubUser.transaction do
        @user = RpgClubUser.lock.find_by(user_id: @user_id)
        MemberDashboardPanel.where(user_id: @user_id).delete_all
        @user&.update!(dashboard_panels_customised: false)
      end
      @keys = nil
    end

    # Marks every panel as seen (the member opened edit mode).
    def seen!
      @user ||= RpgClubUser.create_or_find_by!(user_id: @user_id)
      @user.update!(dashboard_panels_seen_at: Time.current)
    end

    private

    # A panel is new when it was added after the member last opened edit
    # mode. A member who never opened it has nothing new: every panel is.
    def new?(panel)
      seen_at = @user&.dashboard_panels_seen_at
      return false if seen_at.nil?

      panel.added_on.in_time_zone("UTC") > seen_at
    end

    # The member's row, locked for this transaction (created on their first
    # save), and their list as it stands under the lock.
    def lock_member
      @user = RpgClubUser.lock.find_by(user_id: @user_id) || RpgClubUser.create_or_find_by!(user_id: @user_id).lock!
      @keys = nil
    end

    def write(saved)
      MemberDashboardPanel.where(user_id: @user_id).delete_all
      unless saved.empty?
        now = Time.current
        MemberDashboardPanel.insert_all!(saved.each_with_index.map do |key, position|
          { user_id: @user_id, panel_key: key, position: position, created_at: now }
        end)
      end
      @user.update!(dashboard_panels_customised: true)
      @keys = saved
    end

    # Why `panels` isn't a list of panel keys to save at all, or nil.
    def shape_error(panels)
      return "panels must be a list of panel keys" unless panels.is_a?(Array)

      unknown = panels.find { |key| !DashboardPanels.known?(key) }
      return "unknown panel: #{unknown}" unless unknown.nil?

      duplicate = panels.tally.find { |_key, count| count > 1 }&.first
      "#{duplicate} is shown twice" if duplicate
    end

    # Panels in the member's list they can't see right now.
    def hidden = keys.reject { |key| @viewer.sees?(key) }
  end
end
