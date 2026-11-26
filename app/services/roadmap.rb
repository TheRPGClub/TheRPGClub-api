# frozen_string_literal: true

# The Roadmap (GLOSSARY.md "Roadmap"; spec api#505). Staff editing (ticket
# api#507) keeps its rules here: Milestones (Roadmap::Milestones), including
# Reach and un-reach, and Roadmap Items (Roadmap::Items), including moves and
# Shipped. Every write runs in one transaction under one advisory lock
# (Roadmap.write), so two staff editing at once can't interleave positions.
module Roadmap
  # A change the rules refuse: rendered as 422 `{ error: code, message: }`.
  class Refused < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  # Runs the block in a transaction holding the Roadmap's write lock.
  def self.write
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtext('roadmap'))")
      yield
    end
  end

  # `ids` as integers when they name exactly `current` (each once, in any
  # order), else refuses with `invalid_order`.
  def self.full_order!(ids, current, message)
    ids = Array(ids).map { |id| id.is_a?(Integer) ? id : Integer(id.to_s, 10, exception: false) }
    raise Refused.new("invalid_order", message) unless ids.none?(&:nil?) && ids.sort == current.sort

    ids
  end

  # Sets `position` on `model`'s rows from `positions` (id => position) in
  # one statement.
  def self.set_positions!(model, positions)
    return if positions.empty?

    sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, positions.keys, positions.values ])
      UPDATE #{model.table_name} SET position = ordered.position, updated_at = now()
      FROM unnest(ARRAY[?]::bigint[], ARRAY[?]::int[]) AS ordered(id, position)
      WHERE #{model.table_name}.id = ordered.id
    SQL
    model.connection.exec_update(sql, "Roadmap positions")
  end
end
