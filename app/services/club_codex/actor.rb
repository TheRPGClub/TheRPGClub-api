# frozen_string_literal: true

module ClubCodex
  # The member acting on the Club Codex, signed in or through the bot, and
  # what they may do (spec #397, "Permissions"). The API decides from the
  # member's stored roles, never from the bot's token (docs/adr/0005).
  # Mentioned members get no say over an entry.
  #
  # Lore Entries and Fun Facts:
  #   create          Regulars, Moderators, Admins and Superadmins
  #   edit, delete    the author, for their own; a Moderator or above, for any
  Actor = Data.define(:user_id, :regular, :moderator) do
    def regular? = regular
    def moderator_or_above? = moderator

    def can_create? = regular? || moderator_or_above?

    def author_of?(entry) = user_id.present? && entry.author_user_id == user_id

    def can_edit?(entry) = moderator_or_above? || author_of?(entry)

    def can_delete?(entry) = moderator_or_above? || author_of?(entry)

    # The `viewer` flags every entry payload carries, so clients don't
    # re-implement these rules.
    def viewer(entry) = { can_edit: can_edit?(entry), can_delete: can_delete?(entry) }
  end

  # The refusal messages members see, as the bot and the website show them.
  module Refusals
    CREATE = "You need the Regulars role to add to the Club Codex."
    EDIT = "Only its author or a Moderator can edit this."
    DELETE = "Only its author or a Moderator can delete this."
  end
end
