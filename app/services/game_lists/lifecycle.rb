# frozen_string_literal: true

module GameLists
  # Changing a Game List itself: its fields, its visibility, and deleting it.
  # Every edit and delete goes through here, so the rules for a list that
  # feeds a Challenge live in one place (spec api#442, "Takeover"; ticket
  # api#448):
  #
  #   - Deleting a list that feeds a Challenge, or making it Private, is
  #     refused with 409 `list_feeds_challenges` (naming the Challenges)
  #     unless `confirm`.
  #   - Delete: a member's list goes to the club (Challenges::ListLink.take_over!)
  #     and keeps feeding; a club list is deleted, and the Challenges'
  #     links end, keeping their games (Challenges::ListLink.end!).
  #   - Private: the club keeps a Members-visible copy the Challenges relink
  #     to (Challenges::ListLink.copy_for_club!); the owner's list goes
  #     Private.
  #
  # The Challenges are locked before the list, as Challenge writes that
  # touch the list lock them.
  module Lifecycle
    module_function

    # Saves `attributes` (name, description, visibility, sort) on the list.
    # Raises ActiveRecord::RecordInvalid when the list's rules refuse them.
    def update!(list, attributes, confirm: false)
      going_private = attributes["visibility"] == GameList::PRIVATE && !list.private?
      GameList.transaction do
        challenges = going_private ? Challenges::ListLink.lock_linked(list) : []
        refuse_unconfirmed(challenges, confirm, "making it Private keeps a copy for the club")
        list.update!(attributes)
        Challenges::ListLink.copy_for_club!(list, challenges) if challenges.any?
      end
      list
    end

    # Deletes the list with its entries, or hands it to the club when it
    # feeds a Challenge. Returns whether the club took it over.
    def destroy!(list, confirm: false)
      GameList.transaction do
        challenges = Challenges::ListLink.lock_linked(list)
        if challenges.any? && !list.club?
          refuse_unconfirmed(challenges, confirm, "the club will keep it")
          Challenges::ListLink.take_over!(list)
          next true
        end

        refuse_unconfirmed(challenges, confirm, "deleting it ends the link, and the Challenges keep their games")
        challenges.each { |challenge| Challenges::ListLink.end!(challenge) }
        list.destroy!
        false
      end
    end

    def refuse_unconfirmed(challenges, confirm, outcome)
      return if challenges.empty? || confirm

      names = challenges.map(&:name)
      raise Refused.new("list_feeds_challenges",
        "This Game List feeds #{names.to_sentence}, so #{outcome}. Send confirm to go ahead.",
        status: :conflict, challenges: challenges.map { |challenge| { id: challenge.id, name: challenge.name } })
    end
    private_class_method :refuse_unconfirmed
  end
end
