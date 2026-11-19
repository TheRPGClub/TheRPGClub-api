# frozen_string_literal: true

module PinnedPages
  # A member's Pinned Pages: their saved list in order, or the club default
  # until they first save one (`pinned_pages_customised` on the member).
  #
  # Reads give only the pages the member can see right now. A save replaces
  # the list the member sees but keeps the pins they can't see (a Feature Off
  # or hidden by a Feature Preference, a staff role lost), after the saved
  # ones and in their existing order, so they return when the page does. The
  # limit counts both.
  #
  # Saved keys the API no longer knows (a removed page) are ignored on read
  # and dropped on the member's next save (docs/adr/0012).
  class List
    # `user` is the member's record, nil when they have none yet.
    def initialize(user_id, viewer, user)
      @user_id = user_id
      @viewer = viewer
      @user = user
    end

    # Whether the member saved their own list, rather than following DEFAULT.
    def customised? = @user&.pinned_pages_customised || false

    # Every known key in the member's list, seen or not.
    def keys
      @keys ||= if customised?
        MemberPinnedPage.where(user_id: @user_id).order(:position).pluck(:page_key)
          .select { |key| PinnedPages.known?(key) }
      else
        DEFAULT.dup
      end
    end

    # The pages the member can see right now, in their order.
    def visible = keys.select { |key| @viewer.sees?(key) }

    # How many pins the member can see room for: LIMIT less the pins they
    # can't see right now, which a save keeps and the limit counts.
    def room = [ LIMIT - hidden.size, 0 ].max

    # Saves `pages` (the list the member sees, in order) plus the kept hidden
    # pins as the member's whole list. Returns why it can't, changing
    # nothing, or nil once saved.
    #
    # The member's row is locked first and the list read under it, so two
    # saves at once run one after the other, and the second checks the limit
    # against the pins the first kept.
    def save(pages)
      error = shape_error(pages)
      return error if error

      RpgClubUser.transaction do
        lock_member
        hidden_now = kept_hidden(pages)
        if pages.size + hidden_now.size > LIMIT
          error = limit_error(hidden_now.size)
        else
          write(pages + hidden_now)
        end
      end
      error
    end

    # Drops the member's saved list, so they follow DEFAULT again, including
    # later changes to it.
    def reset!
      RpgClubUser.transaction do
        @user = RpgClubUser.lock.find_by(user_id: @user_id)
        MemberPinnedPage.where(user_id: @user_id).delete_all
        @user&.update!(pinned_pages_customised: false)
      end
      @keys = nil
    end

    private

    # The member's row, locked for this transaction (created on their first
    # save), and their list as it stands under the lock.
    def lock_member
      @user = RpgClubUser.lock.find_by(user_id: @user_id) || RpgClubUser.create_or_find_by!(user_id: @user_id).lock!
      @keys = nil
    end

    def write(saved)
      MemberPinnedPage.where(user_id: @user_id).delete_all
      unless saved.empty?
        now = Time.current
        MemberPinnedPage.insert_all!(saved.each_with_index.map do |key, position|
          { user_id: @user_id, page_key: key, position: position, created_at: now }
        end)
      end
      @user.update!(pinned_pages_customised: true)
      @keys = saved
    end

    # Why `pages` isn't a list of page keys to save at all, or nil.
    def shape_error(pages)
      return "pages must be a list of page keys" unless pages.is_a?(Array)

      unknown = pages.find { |key| !PinnedPages.known?(key) }
      return "unknown page: #{unknown}" unless unknown.nil?

      duplicate = pages.tally.find { |_key, count| count > 1 }&.first
      "#{duplicate} is pinned twice" if duplicate
    end

    def limit_error(hidden) = "at most #{LIMIT} Pinned Pages, counting #{hidden} you can't see right now"

    # Pins in the member's list they can't see right now.
    def hidden = keys.reject { |key| @viewer.sees?(key) }

    # Those of them the member didn't send.
    def kept_hidden(pages) = hidden - pages
  end
end
