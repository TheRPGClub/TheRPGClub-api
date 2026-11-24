# frozen_string_literal: true

module GameLists
  # A Game List's entries (spec api#442): adding a game, its note, removing
  # it and the ranked order. Each write holds the list's lock, so the
  # 500-entry limit and the positions stay right under concurrent edits, and
  # touches the list, so it moves up the index. Adding and removing tell the
  # Challenges the list feeds (Challenges::ListLink): a Core Game removed
  # opens a list notice, and one added back clears it.
  #
  # Positions run 1..n in the ranked order: a new game goes last, and
  # removing one closes the gap. The ranked order is kept whatever the
  # list's sort, so switching back to Ranked restores it.
  module Entries
    module_function

    # Adds the game last in the ranked order. 404 for an unknown game, 409
    # `already_in_list` for one the list has, 422 `list_full` at the limit.
    def add!(list, game_id, note: nil)
      game = GamedbGame.find(game_id)
      list.with_lock do
        if list.entries.exists?(game_id: game.game_id)
          raise Refused.new("already_in_list", "#{game.title} is already in this list.", status: :conflict)
        end

        count = list.entries.count
        if count >= GameList::ENTRIES_MAX
          raise Refused.new("list_full", "A Game List holds at most #{GameList::ENTRIES_MAX} games.")
        end

        entry = list.entries.create!(game_id: game.game_id, note: note, position: count + 1, added_at: Time.current)
        Challenges::ListLink.entry_added!(list, game.game_id)
        entry
      end
    end

    # Replaces the game's note; blank removes it.
    def note!(list, game_id, note)
      entry = list.entries.find_by!(game_id: game_id)
      entry.update!(note: note)
      entry
    end

    # Removes the game and closes the gap in the ranked order. The
    # Challenges the list feeds are locked first, as Challenge writes that
    # touch the list lock them (Challenges::ListLink).
    def remove!(list, game_id)
      GameList.transaction do
        Challenges::ListLink.lock_linked(list)
        list.lock!
        entry = list.entries.find_by!(game_id: game_id)
        entry.destroy!
        list.entries.where("position > ?", entry.position).update_all("position = position - 1")
        Challenges::ListLink.entry_removed!(list, entry.game_id)
        entry
      end
    end

    # Sets the ranked order to `game_ids`, which must name every game of the
    # list once (422 `invalid_order` otherwise).
    def reorder!(list, game_ids)
      ids = Array(game_ids).map { |id| Integer(id, exception: false) }
      list.with_lock do
        current = list.entries.pluck(:game_id)
        unless ids.size == current.size && ids.none?(&:nil?) && ids.sort == current.sort
          raise Refused.new("invalid_order", "game_ids must list every game of the list exactly once.")
        end

        update_positions(list, ids)
        list.touch
      end
    end

    def update_positions(list, ids)
      return if ids.empty?

      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, ids, list.id ])
        UPDATE game_list_entries SET position = ordered.position
        FROM unnest(ARRAY[?]::bigint[]) WITH ORDINALITY AS ordered(game_id, position)
        WHERE game_list_entries.game_list_id = ? AND game_list_entries.game_id = ordered.game_id
      SQL
      GameListEntry.connection.exec_update(sql, "GameLists::Entries reorder")
    end
    private_class_method :update_positions
  end
end
