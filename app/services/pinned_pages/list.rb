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
    def initialize(user_id, viewer)
      @user_id = user_id
      @viewer = viewer
    end

    # Whether the member saved their own list, rather than following DEFAULT.
    def customised?
      @customised = RpgClubUser.where(user_id: @user_id, pinned_pages_customised: true).exists? if @customised.nil?
      @customised
    end

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

    # Why `pages` (the list the member sees, in order) can't be saved, or nil.
    def error_for(pages)
      return "pages must be a list of page keys" unless pages.is_a?(Array)

      unknown = pages.find { |key| !PinnedPages.known?(key) }
      return "unknown page: #{unknown}" unless unknown.nil?

      duplicate = pages.tally.find { |_key, count| count > 1 }&.first
      return "#{duplicate} is pinned twice" if duplicate

      hidden = kept_hidden(pages).size
      return if pages.size + hidden <= LIMIT

      "at most #{LIMIT} Pinned Pages, counting #{hidden} you can't see right now"
    end

    # Saves `pages` (checked with error_for first) plus the kept hidden pins
    # as the member's whole list.
    def replace!(pages)
      saved = pages + kept_hidden(pages)
      RpgClubUser.transaction do
        user = RpgClubUser.find_or_create_by!(user_id: @user_id)
        MemberPinnedPage.where(user_id: @user_id).delete_all
        unless saved.empty?
          now = Time.current
          MemberPinnedPage.insert_all!(saved.each_with_index.map do |key, position|
            { user_id: @user_id, page_key: key, position: position, created_at: now }
          end)
        end
        user.update!(pinned_pages_customised: true)
      end
      @customised = true
      @keys = saved
    end

    # Drops the member's saved list, so they follow DEFAULT again, including
    # later changes to it.
    def reset!
      RpgClubUser.transaction do
        MemberPinnedPage.where(user_id: @user_id).delete_all
        RpgClubUser.where(user_id: @user_id).update_all(pinned_pages_customised: false)
      end
      @customised = false
      @keys = nil
    end

    private

    # Pins in the member's list they can't see right now and didn't send.
    def kept_hidden(pages)
      keys.reject { |key| @viewer.sees?(key) || pages.include?(key) }
    end
  end
end
