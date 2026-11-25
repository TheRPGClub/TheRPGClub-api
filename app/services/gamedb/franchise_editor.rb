# frozen_string_literal: true

module Gamedb
  # Every hand change to a Franchise goes through here (spec api#442,
  # "Franchises (API)"): linking and unlinking games, setting Mainline,
  # setting or clearing a game's Add-on parent, creating, renaming, merging
  # and deleting Franchises, and undoing a change. Permission checks stay with the caller; this only applies a
  # change for the member who made it.
  #
  #   editor = Gamedb::FranchiseEditor.new(user_id: "123")
  #   editor.link!(franchise, game, mainline: true)
  #   editor.link!(franchise, game, parent: other_game)  # or parent: nil
  #   editor.unlink!(franchise, game)
  #   editor.create!(name: "Soulslike")
  #   editor.rename!(franchise, name: "FF")
  #   editor.merge!(franchise, into: other)
  #   editor.delete!(franchise)
  #   editor.undo!(change)
  #
  # Edits survive IGDB re-imports (IgdbGameImporter#sync_franchises!): a link
  # added here is `manual`, which a re-import never removes; an unlink is
  # remembered in `gamedb_franchise_unlinks`, which a re-import never links
  # again; a re-import never touches `mainline`; and a parent set or cleared
  # here locks it (`gamedb_games.parent_locked`), which a re-import keeps.
  #
  # Links, unlinks, Mainline changes and undos run Franchises::ConquestCheck
  # (a parent change in every Franchise of the game, as Add-ons leave the
  # Mainline set);
  # a merge moves the source's Conquests to the target, and a delete removes
  # them.
  #
  # Each change is one Change, applied in a transaction by #apply!, which is
  # the single place that records it in the history (GamedbFranchiseChange)
  # and invalidates what shows it (the cached game relations and the
  # /franchises tiles, Franchises::BrowseVersion). An undo writes no new row:
  # it marks the change undone.
  class FranchiseEditor
    # A refused merge: `reason` is :invalid_merge (into itself) or
    # :franchise_merged (either side was already merged).
    class MergeRefused < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    # A refused Add-on parent: `reason` is one of PARENT_REFUSALS.
    class ParentRefused < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    # :parent_is_self, :parent_not_igdb (the parent has no IGDB id, which is
    # how Add-ons point at it), :parent_is_add_on and :game_has_add_ons (no
    # Add-ons of Add-ons).
    PARENT_REFUSALS = %i[parent_is_self parent_not_igdb parent_is_add_on game_has_add_ons].freeze

    # A refused undo: `reason` is :not_undoable (create, merge, delete),
    # :already_undone, or :superseded (a later change, a merge or a change
    # outside the history touched the same game or name).
    class UndoRefused < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    # One change to a Franchise. `action` is one of ACTIONS; `game` is nil
    # for a change to the Franchise itself; `before`/`after` hold the changed
    # values (nil when the thing didn't exist before, or doesn't after).
    Change = Data.define(:action, :franchise, :game, :before, :after, :user_id)

    ACTIONS = GamedbFranchiseChange::ACTIONS

    def initialize(user_id:)
      @user_id = user_id
    end

    # Link `game` to `franchise` (as `manual`) if it isn't already, and set
    # Mainline when `mainline` is true or false (nil leaves it as it is).
    # Linking forgets a past unlink of the pair. An IGDB link keeps its
    # source. `parent` makes the game an Add-on of that GamedbGame, nil stops
    # it being one, and :keep (the default) leaves it; either way the parent
    # is then locked against IGDB re-imports. Raises ParentRefused (nothing
    # changes). Returns the link.
    def link!(franchise, game, mainline: nil, parent: :keep)
      GamedbGameFranchise.transaction do
        link = GamedbGameFranchise.lock.find_by(franchise_id: franchise.franchise_id, game_id: game.game_id)
        link ||= add_link!(franchise, game)
        parent_changed = parent != :keep && set_parent!(franchise, game, parent)
        set_mainline!(link, franchise, game, mainline) unless mainline.nil? || link.mainline == mainline
        parent_changed ? check_game_conquests!(game.game_id) : check_conquests!(franchise)
        link
      end
    end

    # Remove `game` from `franchise` and remember it, so a re-import doesn't
    # add it back. Nothing happens when the game isn't linked.
    def unlink!(franchise, game)
      GamedbGameFranchise.transaction do
        link = GamedbGameFranchise.lock.find_by(franchise_id: franchise.franchise_id, game_id: game.game_id)
        next if link.nil?

        before = link_values(link).merge("created_at" => link.created_at&.iso8601(6), "created_by" => link.created_by)
        apply!(:unlink, franchise, game, before: before, after: nil) do
          link.destroy!
          GamedbFranchiseUnlink.upsert(
            { game_id: game.game_id, franchise_id: franchise.franchise_id, unlinked_by: @user_id,
              unlinked_at: Time.current },
            unique_by: %i[game_id franchise_id]
          )
        end
        check_conquests!(franchise)
      end
    end

    # A new Franchise with no IGDB id. Raises ActiveRecord::RecordInvalid
    # for a blank or too-long name.
    def create!(name:)
      GamedbFranchise.transaction do
        franchise = GamedbFranchise.new(name: name.to_s.squish, created_by: @user_id)
        franchise.validate!
        apply!(:create, franchise, nil, before: nil, after: { "name" => franchise.name }) { franchise.save! }
        franchise
      end
    end

    # Rename `franchise` and lock the name, so a re-import keeps it. Raises
    # ActiveRecord::RecordInvalid for a blank or too-long name. Nothing is
    # recorded when the name is already this one and locked.
    def rename!(franchise, name:)
      GamedbFranchise.transaction do
        franchise.lock!
        before = name_values(franchise)
        franchise.assign_attributes(name: name.to_s.squish, name_locked: true)
        franchise.validate!
        next franchise unless franchise.changed?

        apply!(:rename, franchise, nil, before: before, after: name_values(franchise)) { franchise.save! }
        touch_games!(franchise.franchise_id)
        franchise
      end
    end

    # Merge `source` into `into`: its links move (a game in both stays
    # Mainline if it was in either), its remembered unlinks move unless the
    # target links the game, its Pool sources point at the target, and it
    # keeps its row with `merged_into_id`, so re-imports naming its IGDB id
    # resolve to the target. Franchises merged into `source` earlier now
    # point at the target. Recorded in the target's history. Raises
    # MergeRefused.
    def merge!(source, into:)
      raise MergeRefused, :invalid_merge if source.franchise_id == into.franchise_id

      GamedbFranchise.transaction do
        source.lock!
        into.lock!
        raise MergeRefused, :franchise_merged if source.merged? || into.merged?

        game_ids = GamedbGameFranchise.where(franchise_id: source.franchise_id).pluck(:game_id)
        before = { "franchise_id" => source.franchise_id, "name" => source.name,
                   "igdb_franchise_id" => source.igdb_franchise_id, "games" => game_ids.size }
        apply!(:merge, into, nil, before: before, after: { "franchise_id" => into.franchise_id, "name" => into.name }) do
          move_links!(source.franchise_id, into.franchise_id)
          move_pool_sources!(source.franchise_id, into.franchise_id)
          move_conquests!(source.franchise_id, into.franchise_id)
          GamedbFranchise.where(merged_into_id: source.franchise_id).update_all(merged_into_id: into.franchise_id)
          source.update!(merged_into_id: into.franchise_id)
        end
        GamedbGame.where(game_id: game_ids).touch_all
        into
      end
    end

    # Delete `franchise`: its links and Pool sources go (a Pool's Core
    # Games are its own rows and stay), and its IGDB id is remembered so a
    # re-import doesn't create it again. Franchises merged into it go with
    # it. Its history stays.
    def delete!(franchise)
      GamedbFranchise.transaction do
        franchise.lock!
        merged = GamedbFranchise.where(merged_into_id: franchise.franchise_id).to_a
        ids = [ franchise.franchise_id, *merged.map(&:franchise_id) ]
        game_ids = GamedbGameFranchise.where(franchise_id: ids).pluck(:game_id)
        before = { "name" => franchise.name, "igdb_franchise_id" => franchise.igdb_franchise_id,
                   "games" => game_ids.size }
        apply!(:delete, franchise, nil, before: before, after: nil) do
          [ franchise, *merged ].each { |gone| remember_deleted!(gone) }
          ChallengePoolFranchise.where(franchise_id: ids).delete_all
          UserFranchiseConquest.where(franchise_id: ids).delete_all
          GamedbGameFranchise.where(franchise_id: ids).delete_all
          GamedbFranchiseUnlink.where(franchise_id: ids).delete_all
          GamedbFranchise.where(franchise_id: merged.map(&:franchise_id)).delete_all
          franchise.destroy!
        end
        GamedbGame.where(game_id: game_ids).touch_all
        nil
      end
    end

    # Undo `change` (a GamedbFranchiseChange): put back what it changed and
    # mark it undone. Raises UndoRefused.
    def undo!(change)
      GamedbFranchise.transaction do
        change.lock!
        raise UndoRefused, :not_undoable unless change.undoable_action?
        raise UndoRefused, :already_undone if change.undone_at

        franchise = GamedbFranchise.lock.find_by(franchise_id: change.franchise_id)
        raise UndoRefused, :superseded if franchise.nil? || franchise.merged? || change.superseded?
        raise UndoRefused, :superseded unless revert!(change, franchise)

        change.update!(undone_at: Time.current, undone_by: @user_id)
        change.action == "parent" ? check_game_conquests!(change.game_id) : check_conquests!(franchise)
        change.game_change? ? GamedbGame.where(game_id: change.game_id).touch_all : touch_games!(franchise.franchise_id)
        Franchises::BrowseVersion.bump!
        change
      end
    end

    private

    def add_link!(franchise, game)
      link = GamedbGameFranchise.new(franchise_id: franchise.franchise_id, game_id: game.game_id,
        source: "manual", mainline: false, created_by: @user_id, created_at: Time.current)
      unlinks = GamedbFranchiseUnlink.where(franchise_id: franchise.franchise_id, game_id: game.game_id)
      apply!(:link, franchise, game, before: unlink_values(unlinks.first), after: link_values(link)) do
        unlinks.delete_all
        link.save!
      end
      link
    end

    # A link that replaced a remembered unlink records it in `before`, so
    # undoing the link remembers it again.
    def unlink_values(unlink)
      unlink && { "unlinked_by" => unlink.unlinked_by, "unlinked_at" => unlink.unlinked_at.iso8601(6) }
    end

    def name_values(franchise) = { "name" => franchise.name, "name_locked" => franchise.name_locked }

    # Puts back what `change` changed when the Franchise still shows its
    # `after`; false (nothing done) when something else changed it since.
    def revert!(change, franchise)
      return revert_rename!(change, franchise) if change.action == "rename"
      return revert_parent!(change) if change.action == "parent"

      link = GamedbGameFranchise.lock.find_by(franchise_id: franchise.franchise_id, game_id: change.game_id)
      case change.action
      when "link" then revert_link!(change, link)
      when "unlink" then revert_unlink!(change, link)
      else revert_mainline!(change, link)
      end
    end

    def revert_rename!(change, franchise)
      return false unless franchise.name == change.after["name"]

      franchise.update!(change.before.slice("name", "name_locked"))
    end

    # Puts back the parent and its lock, when the game still has the parent
    # the change gave it.
    def revert_parent!(change)
      game = GamedbGame.lock.find_by(game_id: change.game_id)
      return false if game.nil? || parent_values(game).slice(*PARENT_KEYS) != change.after.slice(*PARENT_KEYS)

      game.update!(change.before.slice(*PARENT_KEYS))
    end

    def revert_link!(change, link)
      return false if link.nil?

      link.destroy!
      return true if change.before.nil?

      GamedbFranchiseUnlink.create!(franchise_id: change.franchise_id, game_id: change.game_id,
        unlinked_by: change.before["unlinked_by"], unlinked_at: change.before["unlinked_at"])
    end

    def revert_unlink!(change, link)
      return false unless link.nil?

      GamedbFranchiseUnlink.where(franchise_id: change.franchise_id, game_id: change.game_id).delete_all
      GamedbGameFranchise.create!(franchise_id: change.franchise_id, game_id: change.game_id,
        **change.before.slice("source", "mainline", "created_at", "created_by").symbolize_keys)
    end

    def revert_mainline!(change, link)
      return false if link.nil? || link.mainline != change.after["mainline"]

      link.update!(mainline: change.before["mainline"])
    end

    # Moves `from`'s links to `to` (merging Mainline with OR), and its
    # remembered unlinks where `to` doesn't link the game. An unlink of
    # `to`'s own goes for a game the merge now links.
    def move_links!(from, to)
      from_links = GamedbGameFranchise.where(franchise_id: from)
      to_links = GamedbGameFranchise.where(franchise_id: to)
      to_links.where(game_id: from_links.where(mainline: true).select(:game_id)).update_all(mainline: true)
      from_links.where(game_id: to_links.select(:game_id)).delete_all
      GamedbFranchiseUnlink.where(franchise_id: to, game_id: from_links.select(:game_id)).delete_all
      from_links.update_all(franchise_id: to)

      from_unlinks = GamedbFranchiseUnlink.where(franchise_id: from)
      from_unlinks.where(game_id: to_links.select(:game_id)).delete_all
      from_unlinks.where(game_id: GamedbFranchiseUnlink.where(franchise_id: to).select(:game_id)).delete_all
      from_unlinks.update_all(franchise_id: to)
    end

    def move_pool_sources!(from, to)
      sources = ChallengePoolFranchise.where(franchise_id: from)
      sources.where(challenge_id: ChallengePoolFranchise.where(franchise_id: to).select(:challenge_id)).delete_all
      sources.update_all(franchise_id: to)
    end

    # Moves `from`'s Conquests to `to`. A member with a Conquest in both
    # keeps the earlier one.
    def move_conquests!(from, to)
      kept = UserFranchiseConquest.where(franchise_id: to).pluck(:user_id, :id, :conquered_at).to_h { |user_id, *rest| [ user_id, rest ] }
      UserFranchiseConquest.where(franchise_id: from).pluck(:id, :user_id, :conquered_at).each do |id, user_id, conquered_at|
        target_id, target_at = kept[user_id]
        gone = target_id && target_at <= conquered_at ? id : target_id
        UserFranchiseConquest.where(id: gone).delete_all if gone
        UserFranchiseConquest.where(id: id).update_all(franchise_id: to) unless gone == id
      end
    end

    # Linking, unlinking and Mainline changes can finish a member's
    # Mainline set (spec api#457). Those Conquests are announced.
    def check_conquests!(franchise)
      Franchises::ConquestCheck.new(requested_by: @user_id).for_franchise(franchise)
    end

    def remember_deleted!(franchise)
      return if franchise.igdb_franchise_id.nil?

      GamedbDeletedFranchise.upsert(
        { igdb_franchise_id: franchise.igdb_franchise_id, name: franchise.name, deleted_by: @user_id,
          deleted_at: Time.current },
        unique_by: :igdb_franchise_id
      )
    end

    # A parent change can move a game into or out of the Mainline set of
    # every Franchise that links it.
    def check_game_conquests!(game_id)
      GamedbFranchise.current.where(franchise_id: GamedbGameFranchise.where(game_id: game_id).select(:franchise_id))
        .find_each { |franchise| check_conquests!(franchise) }
    end

    # A rename shows in every game's relations.
    def touch_games!(franchise_id)
      GamedbGame.where(game_id: GamedbGameFranchise.where(franchise_id: franchise_id).select(:game_id)).touch_all
    end

    def set_mainline!(link, franchise, game, mainline)
      action = mainline ? :mainline_on : :mainline_off
      apply!(action, franchise, game, before: { "mainline" => link.mainline },
        after: { "mainline" => mainline }) do
        link.update!(mainline: mainline)
      end
    end

    def link_values(link) = { "source" => link.source, "mainline" => link.mainline }

    # What a `parent` change puts back; `parent_game_id` is recorded too, for
    # the history to link the parent.
    PARENT_KEYS = %w[parent_igdb_id parent_game_name parent_locked].freeze

    # Gives `game` the parent `parent` (a GamedbGame, or nil for none) and
    # locks it. Records nothing when the game already has that parent,
    # locked. Returns whether anything changed. Raises ParentRefused.
    def set_parent!(franchise, game, parent)
      record = GamedbGame.lock.find(game.game_id)
      refuse_parent!(record, parent) if parent

      before = parent_values(record)
      record.assign_attributes(parent_igdb_id: parent&.igdb_id, parent_game_name: parent&.title, parent_locked: true)
      return false unless record.changed?

      apply!(:parent, franchise, game, before: before, after: parent_values(record, parent_game_id: parent&.game_id)) do
        record.save!
      end
      true
    end

    def refuse_parent!(game, parent)
      raise ParentRefused, :parent_is_self if parent.game_id == game.game_id
      raise ParentRefused, :parent_not_igdb if parent.igdb_id.nil?
      raise ParentRefused, :parent_is_add_on if parent.parent_igdb_id.present?
      raise ParentRefused, :game_has_add_ons if game.igdb_id && GamedbGame.exists?(parent_igdb_id: game.igdb_id)
    end

    def parent_values(game, parent_game_id: :lookup)
      if parent_game_id == :lookup
        parent_game_id = game.parent_igdb_id && GamedbGame.where(igdb_id: game.parent_igdb_id).pick(:game_id)
      end
      { "parent_game_id" => parent_game_id, "parent_igdb_id" => game.parent_igdb_id,
        "parent_game_name" => game.parent_game_name, "parent_locked" => game.parent_locked }
    end

    # The one path every change takes: apply it, record it, and invalidate
    # what shows it. Runs inside the caller's transaction.
    def apply!(action, franchise, game, before:, after:)
      yield
      record!(Change.new(action: action.to_s, franchise: franchise, game: game, before: before, after: after,
        user_id: @user_id))
      # A game's relations (GamesController#relations_data) are cached on
      # its updated_at and list its Franchises.
      game&.touch
      Franchises::BrowseVersion.bump!
    end

    # Writes `change` to the Franchise's history.
    def record!(change)
      GamedbFranchiseChange.create!(franchise_id: change.franchise.franchise_id, game_id: change.game&.game_id,
        action: change.action, before: change.before, after: change.after, user_id: change.user_id)
    end
  end
end
