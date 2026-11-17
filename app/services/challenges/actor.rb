# frozen_string_literal: true

module Challenges
  # The member acting on Challenges, signed in or through the bot, and what
  # they may do (spec #376, "Who can do what"). The API decides from the
  # member's stored roles, never from the bot's token (docs/adr/0005).
  #
  #   create          Regulars, Moderators, Admins and Superadmins; a
  #                   club-hosted Challenge needs a Moderator or above
  #   edit            the Host, for their own; a Moderator or above for a
  #                   club-hosted one
  #   delete          the Host while it has no Runs; a Moderator or above
  #                   removes any
  #   hide, unhide, change Host
  #                   a Moderator or above
  #   see hidden      a Moderator or above, and the Host
  Actor = Data.define(:user_id, :regular, :moderator) do
    def regular? = regular
    def moderator_or_above? = moderator

    def can_create? = regular? || moderator_or_above?

    def can_host_for_club? = moderator_or_above?

    def host_of?(challenge) = !challenge.club_hosted? && user_id.present? && challenge.host_user_id == user_id

    def can_edit?(challenge) = challenge.club_hosted? ? moderator_or_above? : host_of?(challenge)

    def can_delete?(challenge) = moderator_or_above? || host_of?(challenge)

    def can_moderate? = moderator_or_above?

    def can_see?(challenge) = !challenge.hidden? || moderator_or_above? || host_of?(challenge)
  end

  # The refusal messages members see, as the bot and the website show them.
  module Refusals
    CREATE = "You need the Regulars role to create a Challenge."
    CLUB_HOSTED = "Only Moderators and above can create a Challenge hosted by the club."
    EDIT = "Only the Host can edit this Challenge; a club-hosted one, any Moderator or above."
    DELETE = "Only the Host or a Moderator can delete this Challenge."
    DELETE_WITH_RUNS = "This Challenge can't be deleted because members have started Runs. A Moderator can remove it."
    MODERATE = "Only Moderators and above can do that."
  end
end
