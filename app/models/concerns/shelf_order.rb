# frozen_string_literal: true

# A member's hand-ordered shelf list (Now Playing, Backlog, Favorites; spec
# api#451 story 15). `sort_order` is nullable and not unique (the bot and old
# rows leave gaps, duplicates and nulls), so a single move can't be expressed
# as one `sort_order` value. `move_to_position!` instead places the entry at a
# 1-based position in the list's display order and renumbers the member's
# whole list 1..n in one statement, under a row lock.
#
# The including model defines `SHELF_ORDER`, the list's display order. It must
# match what the list endpoint renders (Postgres sorts NULL last on ASC, so
# entries without a `sort_order` trail the ordered ones).
module ShelfOrder
  extend ActiveSupport::Concern

  class_methods do
    def shelf_for(user_id)
      where(user_id:).order(self::SHELF_ORDER)
    end
  end

  # Moves this entry to `position` (1-based; past the end means last). Call
  # inside a transaction so the lock holds until commit.
  def move_to_position!(position)
    ids = self.class.shelf_for(user_id).lock.pluck(:entry_id)
    ids.delete(entry_id)
    ids.insert([ position, ids.length + 1 ].min - 1, entry_id)

    values = ids.each_with_index.map { |id, index| "(#{Integer(id)}, #{index + 1})" }.join(", ")
    table = self.class.quoted_table_name
    self.class.connection.exec_update(<<~SQL.squish)
      UPDATE #{table} SET sort_order = v.position
      FROM (VALUES #{values}) AS v(entry_id, position)
      WHERE #{table}.entry_id = v.entry_id AND #{table}.sort_order IS DISTINCT FROM v.position
    SQL
    reload
  end
end
