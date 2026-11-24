# frozen_string_literal: true

module Challenges
  # The member acting on Challenges, signed in or through the bot, and what
  # they may do (spec #376, "Who can do what"). The API decides from the
  # member's stored roles, never from the bot's token (docs/adr/0005).
  #
  #   create          any member, for Slots and Pool; an Assignment
  #                   Challenge, or one hosted by the club, needs a
  #                   Moderator or above (spec api#442)
  #   edit            the Host, for their own; a Moderator or above, for any
  #                   (member-hosted too; grilling Q19)
  #   delete          the Host while it has no Runs; a Moderator or above
  #                   removes any
  #   hide, unhide, change Host
  #                   a Moderator or above
  #   change tint     the Host, for their own; a Moderator or above, for any
  #   decide Pool Proposals, clear list notices
  #                   whoever may edit the Challenge
  #   add to the linked Game List
  #                   only who may touch the list: its owner, or a
  #                   Moderator or above for a club list linked to a
  #                   club-hosted Challenge (a Moderator editing a member's
  #                   Challenge does not)
  #   see hidden      a Moderator or above, and the Host
  Actor = Data.define(:user_id, :regular, :moderator) do
    def regular? = regular
    def moderator_or_above? = moderator

    def can_create?(challenge_format) = challenge_format.to_s != Formats::Assignment::KEY || moderator_or_above?

    def can_host_for_club? = moderator_or_above?

    def host_of?(challenge) = !challenge.club_hosted? && user_id.present? && challenge.host_user_id == user_id

    def can_edit?(challenge) = moderator_or_above? || host_of?(challenge)

    # Pool Proposals are decided, and list notices cleared, by whoever may
    # edit the Pool.
    def can_decide_proposals?(challenge) = can_edit?(challenge)

    # Whether they may add games to `list`, the Game List linked to
    # `challenge` (Challenges::ListLink).
    def can_add_to_list?(challenge, list)
      return false unless list && can_edit?(challenge)
      return challenge.club_hosted? && moderator_or_above? if list.club?

      user_id.present? && list.owner_user_id == user_id
    end

    # Whether they may start `challenge` (hosted by them, or by the club
    # when `club`) from `list`: a member's own list for their own Challenge,
    # a club list for a club-hosted one.
    def can_link_list?(list, club:)
      return club && moderator_or_above? if list.club?

      !club && user_id.present? && list.owner_user_id == user_id
    end

    def can_delete?(challenge) = moderator_or_above? || host_of?(challenge)

    def can_moderate? = moderator_or_above?

    def can_change_tint?(challenge) = moderator_or_above? || host_of?(challenge)

    def can_see?(challenge) = !challenge.hidden? || moderator_or_above? || host_of?(challenge)
  end

  # The refusal messages members see, as the bot and the website show them.
  module Refusals
    CREATE = "Only Moderators and above can create an Assignment Challenge."
    CLUB_HOSTED = "Only Moderators and above can create a Challenge hosted by the club."
    EDIT = "Only the Host or a Moderator can edit this Challenge."
    DELETE = "Only the Host or a Moderator can delete this Challenge."
    DELETE_WITH_RUNS = "This Challenge can't be deleted because members have started Runs. A Moderator can remove it."
    MODERATE = "Only Moderators and above can do that."
    TINT = "Only the Host or a Moderator can change this Challenge's tint."
    DECIDE_PROPOSALS = "Only the Host or a Moderator can accept or decline Pool Proposals."
    LINK_LIST = "Only a Game List's owner can start a Challenge from it, hosted by them; a club list, a Moderator " \
                "or above, for a club-hosted Challenge."
    ADD_TO_LIST = "Only the Game List's owner can add games to it from this Challenge."
  end
end
