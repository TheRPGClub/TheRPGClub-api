# frozen_string_literal: true

module Challenges
  # A Game List linked to the Pool Challenge it started (spec api#442,
  # "Linking a list to a Challenge"; ticket api#448). The link is one way:
  #
  #   create       the list's games are copied in as Core Games
  #                (pool_with_list) and `challenges.pool_game_list_id` set;
  #                only on create, by the list's owner for their own
  #                Challenge, or staff for a club list and a club-hosted
  #                one (Actor#can_link_list?)
  #   live source  the list's games join as Optional Games (PoolSources::LIST)
  #   add_to_list  games the Host adds to the Pool by hand, or accepts from
  #                a Pool Proposal, go into the list too (add_games!)
  #   notices      a Core Game whose entry leaves the list opens a list
  #                notice (entry_removed!), cleared by Remove or Keep
  #                (resolve_notice!), by the game coming back to the list
  #                (entry_added!) or leaving the Core Games (Formats::Pool)
  #   takeover     a linked list its owner deletes goes to the club, and one
  #                made Private leaves a club copy the Challenges relink to
  #                (GameLists::Lifecycle, take_over! and copy_for_club!)
  #   end          handing the Challenge to another Host, or deleting the
  #                club's list, ends the link (end!), keeping the games
  #
  # Writes that touch both a Challenge and its list lock the Challenge
  # first, then the list, so they never deadlock.
  module ListLink
    module_function

    # The list `id` names, if `user_id` may read it: any Members-visible
    # list, or their own Private one.
    def readable(id, user_id)
      list = GameList.find_by(id: Integer(id.to_s, 10))
      list if list && (!list.private? || list.owned_by?(user_id))
    rescue ArgumentError
      nil
    end

    # The create request's `pool` with the list's games as Core Games,
    # except those the request makes Optional or excludes.
    def pool_with_list(pool, list)
      pool = pool.except("game_list_id")
      given = PoolDefinition.parse(pool)
      taken = given.optional_game_ids + given.excluded_game_ids
      core = given.core_game_ids | (list.entries.order(:position).pluck(:game_id) - taken)
      pool.merge("core_game_ids" => core)
    end

    # The Challenges `list` feeds, locked, oldest first.
    def lock_linked(list)
      Challenge.where(pool_game_list_id: list.id).order(:id).lock.to_a
    end

    # Adds the games (those the list lacks) to the Challenge's linked list,
    # last in its ranked order. Raises GameLists::Refused when it is full.
    def add_games!(challenge, game_ids)
      list = GameList.find(challenge.pool_game_list_id)
      (game_ids - list.entries.pluck(:game_id)).each { |game_id| GameLists::Entries.add!(list, game_id) }
    end

    # A game's entry left `list`: each Challenge it feeds that has the game
    # as a Core Game gets a list notice.
    def entry_removed!(list, game_id)
      challenge_ids = ChallengePoolGame.where(inclusion: "core", game_id: game_id,
        challenge_id: Challenge.where(pool_game_list_id: list.id).select(:id)).pluck(:challenge_id)
      return if challenge_ids.empty?

      ChallengePoolListNotice.insert_all(challenge_ids.map { |id| { challenge_id: id, game_id: game_id } },
        unique_by: %i[challenge_id game_id])
    end

    # A game is back in `list`: its notices on the Challenges the list
    # feeds go.
    def entry_added!(list, game_id)
      ChallengePoolListNotice.where(game_id: game_id,
        challenge_id: Challenge.where(pool_game_list_id: list.id).select(:id)).delete_all
    end

    # Ends the Challenge's link. Its Optional Games from the list stay, as
    # picked by hand (joined when their entry was added), unless another
    # source still holds them; its notices go.
    def end!(challenge)
      list_id = challenge.pool_game_list_id
      return unless list_id

      definition = PoolDefinition.of(challenge)
      kept = definition.with(game_list_ids: []).optional_games.select(:game_id)
      rows = GameListEntry.joins(:game).where(game_list_id: list_id, gamedb_games: { parent_igdb_id: nil })
        .where.not(game_id: definition.core_game_ids + definition.optional_game_ids + definition.excluded_game_ids)
        .where.not(game_id: kept).pluck(:game_id, :added_at)
        .map { |game_id, added_at| { challenge_id: challenge.id, game_id: game_id, inclusion: "optional", added_at: added_at } }
      ChallengePoolGame.insert_all!(rows) if rows.any?
      ChallengePoolListNotice.where(challenge_id: challenge.id).delete_all
      challenge.update_columns(pool_game_list_id: nil)
      challenge.pool_games.reset
    end

    # The club takes the list over from its owner, who deleted it.
    def take_over!(list)
      list.update!(owner_user_id: nil, visibility: GameList::MEMBERS, taken_over_from_user_id: list.owner_user_id,
        taken_over_at: Time.current)
    end

    # The club keeps a Members-visible copy of `list`, which its owner is
    # making Private, and `challenges` relink to it.
    def copy_for_club!(list, challenges)
      copy = GameList.create!(owner_user_id: nil, name: list.name, description: list.description, sort: list.sort,
        visibility: GameList::MEMBERS, taken_over_from_user_id: list.owner_user_id, taken_over_at: Time.current)
      rows = list.entries.map do |entry|
        { game_list_id: copy.id, game_id: entry.game_id, position: entry.position, note: entry.note,
          added_at: entry.added_at }
      end
      GameListEntry.insert_all!(rows) if rows.any?
      Challenge.where(id: challenges.map(&:id)).update_all(pool_game_list_id: copy.id)
      copy
    end

    REMOVE = "remove"
    KEEP = "keep"

    # Clears the notice. Remove also takes its game out of the Challenge
    # (through Challenges::Form, so Runs refresh), excluding it when another
    # source would still bring it in.
    def resolve_notice!(challenge, notice_id, action, by:)
      Challenge.transaction do
        challenge.lock!
        notice = ChallengePoolListNotice.where(challenge_id: challenge.id).lock.find(notice_id)
        remove!(challenge, notice.game_id, by: by) if action == REMOVE
        ChallengePoolListNotice.where(id: notice.id).delete_all
      end
      challenge
    end

    def remove!(challenge, game_id, by:)
      definition = PoolDefinition.of(challenge)
      return unless definition.core_game_ids.include?(game_id)

      core = definition.core_game_ids - [ game_id ]
      excluded = definition.excluded_game_ids
      excluded += [ game_id ] if definition.with(core_game_ids: core).optional_games.exists?(game_id: game_id)
      challenge.updated_by = by
      Form.new(challenge, "pool" => { "core_game_ids" => core, "excluded_game_ids" => excluded }).save!
    end
    private_class_method :remove!
  end
end
