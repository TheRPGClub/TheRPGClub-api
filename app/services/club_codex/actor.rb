# frozen_string_literal: true

module ClubCodex
  # The member acting on the Club Codex, signed in or through the bot, and
  # what they may do (spec #397, "Permissions"). The API decides from the
  # member's stored roles, never from the bot's token (docs/adr/0005).
  # Mentioned members get no say over an entry.
  #
  # History Events (Club History is the club's official record):
  #   create, edit, delete   Admins and Superadmins, for any of them
  # Lore Entries and Fun Facts:
  #   create          Regulars, Moderators, Admins and Superadmins
  #   edit, delete    the author, for their own; a Moderator or above, for any
  #
  # A signed-out Visitor (Actor.visitor) may only read, and only Club History.
  # Everyone else (`member`), the bot included, reads all three parts.
  Actor = Data.define(:user_id, :regular, :moderator, :admin, :member) do
    # A signed-out Visitor (Club History is public): reads History Events,
    # and nothing else.
    def self.visitor = new(user_id: nil, regular: false, moderator: false, admin: false, member: false)

    def initialize(user_id:, regular:, moderator:, admin:, member: true) = super

    def regular? = regular
    def moderator_or_above? = moderator
    def admin_or_above? = admin

    # Whether they may add an entry of `part` (CodexEntry::PARTS).
    def can_create?(part)
      return admin_or_above? if part == CodexEntry::HISTORY_EVENT

      regular? || moderator_or_above?
    end

    def author_of?(entry) = user_id.present? && entry.author_user_id == user_id

    def can_edit?(entry)
      return admin_or_above? if entry.history_event?

      moderator_or_above? || author_of?(entry)
    end

    def can_delete?(entry) = can_edit?(entry)

    # The entries of `scope` they may read: all of them, or a Visitor's
    # History Events.
    def readable(scope) = member ? scope : scope.where(part: CodexEntry::HISTORY_EVENT)

    # The entries of `scope` they may edit, by the rules above.
    def editable(scope)
      return scope if admin_or_above?
      return scope.where.not(part: CodexEntry::HISTORY_EVENT) if moderator_or_above?
      return scope.none if user_id.blank?

      scope.where(author_user_id: user_id).where.not(part: CodexEntry::HISTORY_EVENT)
    end

    # The `viewer` flags every entry payload carries, so clients don't
    # re-implement these rules.
    def viewer(entry) = { can_edit: can_edit?(entry), can_delete: can_delete?(entry) }
  end

  # The refusal messages members see, as the bot and the website show them.
  module Refusals
    CREATE = "You need the Regulars role to add to the Club Codex."
    EDIT = "Only its author or a Moderator can edit this."
    DELETE = "Only its author or a Moderator can delete this."
    HISTORY = "Only Admins can change Club History."
  end
end
