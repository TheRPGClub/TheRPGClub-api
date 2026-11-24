# frozen_string_literal: true

module GameLists
  # The member acting on Game Lists, signed in or through the bot, and what
  # they may do (spec api#442, "Who can do what"). The API decides from the
  # member's stored roles, never from the bot's token (docs/adr/0005).
  #
  #   read                a Members-visible list, any member; a Private one,
  #                       only its owner (staff can't read it either)
  #   create              any member, for themselves; a club list needs a
  #                       Moderator or above
  #   edit                the owner; a Moderator or above for a club list
  #                       and any Members-visible list
  #   change visibility   only the owner (a club list is always Members-visible)
  #   delete              the owner; a Moderator or above for a member's
  #                       Members-visible list; an Admin or above for a club list
  Actor = Data.define(:user_id, :moderator, :admin) do
    def moderator_or_above? = moderator
    def admin_or_above? = admin

    def owner_of?(list) = list.owned_by?(user_id)

    def can_read?(list) = !list.private? || owner_of?(list)

    def can_create_club? = moderator_or_above?

    def can_edit?(list)
      return owner_of?(list) if list.private?

      owner_of?(list) || moderator_or_above?
    end

    def can_change_visibility?(list) = owner_of?(list)

    def can_delete?(list)
      return owner_of?(list) if list.private?
      return admin_or_above? if list.club?

      owner_of?(list) || moderator_or_above?
    end

    # The lists of `scope` they may read.
    def readable(scope)
      return scope.members_visible if user_id.blank?

      scope.members_visible.or(scope.where(owner_user_id: user_id))
    end

    # The `viewer` flags every list payload carries, so clients don't
    # re-implement these rules.
    def viewer(list) = { can_edit: can_edit?(list), can_delete: can_delete?(list) }
  end
end
