# frozen_string_literal: true

module Members
  # A member's own ordered list of keys from a list the API owns (docs/adr/0012):
  # their saved list in order, or the club default until they first save one
  # (a `*_customised` flag on the member). PinnedPages::List and
  # DashboardPanels::List are this with their own keys, table and words.
  #
  # Reads give only the keys the member can see right now. A save replaces
  # the list the member sees but keeps the keys they can't see (a Feature Off
  # or hidden by a Feature Preference, a staff role lost), after the saved
  # ones and in their existing order, so they return when they can see them.
  #
  # Saved keys the API no longer knows (a removed one) are ignored on read and
  # dropped on the member's next save.
  #
  # A subclass gives `catalog` (the module with DEFAULT and `known?`), `model`
  # (the member rows), `key_column`, `customised_column` and the words its
  # errors use (`list_name`, `key_name`, `chosen_word`).
  class OrderedList
    # `user` is the member's record, nil when they have none yet.
    def initialize(user_id, viewer, user)
      @user_id = user_id
      @viewer = viewer
      @user = user
    end

    # Whether the member saved their own list, rather than following DEFAULT.
    def customised? = @user&.public_send(customised_column) || false

    # Every known key in the member's list, seen or not.
    def keys
      @keys ||= if customised?
        model.where(user_id: @user_id).order(:position).pluck(key_column).select { |key| catalog.known?(key) }
      else
        catalog::DEFAULT.dup
      end
    end

    # The keys the member can see right now, in their order.
    def visible = keys.select { |key| @viewer.sees?(key) }

    # Saves `sent` (the list the member sees, in order) plus the kept hidden
    # keys as the member's whole list. Returns why it can't, changing
    # nothing, or nil once saved.
    #
    # The member's row is locked first and the list read under it, so two
    # saves at once run one after the other, and the second sees the keys the
    # first kept.
    def save(sent)
      error = shape_error(sent)
      return error if error

      RpgClubUser.transaction do
        lock_member
        kept = hidden - sent
        error = refusal(sent, kept)
        write(sent + kept) unless error
      end
      error
    end

    # Drops the member's saved list, so they follow DEFAULT again, including
    # later changes to it.
    def reset!
      RpgClubUser.transaction do
        @user = RpgClubUser.lock.find_by(user_id: @user_id)
        model.where(user_id: @user_id).delete_all
        @user&.update!(customised_column => false)
      end
      @keys = nil
    end

    private

    # Why saving `sent` plus the `kept` hidden keys is refused, or nil. Run
    # under the member's lock.
    def refusal(_sent, _kept) = nil

    # Keys in the member's list they can't see right now.
    def hidden = keys.reject { |key| @viewer.sees?(key) }

    # The member's row, locked for this transaction (created on their first
    # save), and their list as it stands under the lock.
    def lock_member
      @user = RpgClubUser.lock.find_by(user_id: @user_id) || RpgClubUser.create_or_find_by!(user_id: @user_id).lock!
      @keys = nil
    end

    def write(saved)
      model.where(user_id: @user_id).delete_all
      unless saved.empty?
        now = Time.current
        model.insert_all!(saved.each_with_index.map do |key, position|
          { user_id: @user_id, key_column => key, position: position, created_at: now }
        end)
      end
      @user.update!(customised_column => true)
      @keys = saved
    end

    # Why `sent` isn't a list of keys to save at all, or nil.
    def shape_error(sent)
      return "#{list_name} must be a list of #{key_name} keys" unless sent.is_a?(Array)

      unknown = sent.find { |key| !catalog.known?(key) }
      return "unknown #{key_name}: #{unknown}" unless unknown.nil?

      duplicate = sent.tally.find { |_key, count| count > 1 }&.first
      "#{duplicate} is #{chosen_word} twice" if duplicate
    end
  end
end
