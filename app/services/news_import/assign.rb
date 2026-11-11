# frozen_string_literal: true

module NewsImport
  # Applies a reviewed list of (message id, value) rows to imported News
  # Items (spec #355, ticket #359). A News Category key assigns that News
  # Category, which makes the item visible to members, and records the
  # acting staff member and the time on each item whose News Category this
  # changed (`category_changed_by`, `category_changed_at`; a row repeating
  # the stored category changes nothing); `skip` deletes the item and
  # remembers the removal (NewsImportRemoval). Values ignore case and
  # surrounding spaces. Assigning again changes the News Category, and
  # `skip` for an item already removed counts as removed again, so the same
  # file can be applied twice.
  #
  # Each bad row is rejected with a reason and does not stop the others:
  # a missing or repeated message id, a blank or invalid value, a message id
  # with no News Item, a live (not imported) News Item, or a category for an
  # item removed with `skip`.
  #
  # Returns { assigned:, removed:, rejected:, unsorted:, rejections: [ { index, message_id, value, reason } ],
  # moved: [ { message_id, category_key, previous_category_key, news_copy: { message_id, thread_id } } ] },
  # where `unsorted` is how many imported News Items are still unsorted
  # afterwards and `moved` lists, in row order, the items whose News Category
  # this request changed and that have a News Copy (ticket #369), so the bot
  # can move each copy to its new category's thread. A first assignment to an
  # unsorted item is not a move: an unsorted item has no News Copy.
  class Assign
    SKIP = "skip"
    MAX_ROWS = 5000
    ACCEPTED = "expected one of #{NewsCategory.keys.join(', ')} or #{SKIP}".freeze

    class TooLarge < StandardError; end

    def self.call(rows, by:) = new(rows, by:).call

    def initialize(rows, by:)
      @rows = rows.map { |row| { message_id: row["message_id"].to_s.strip, value: row["value"].to_s } }
      @by = by
    end

    def call
      raise TooLarge, "at most #{MAX_ROWS} rows per request" if @rows.size > MAX_ROWS

      assigned = []
      removals = []
      rejections = []
      @rows.each_with_index do |row, index|
        value = row[:value].strip.downcase
        if (reason = rejection(row[:message_id], value))
          rejections << { index: index, message_id: row[:message_id], value: row[:value], reason: reason }
        elsif value == SKIP
          removals << row[:message_id]
        else
          assigned << [ row[:message_id], value ]
        end
      end

      moved = copies_to_move(assigned)
      apply(assigned, removals)
      {
        assigned: assigned.size, removed: removals.size, rejected: rejections.size,
        unsorted: NewsItem.unsorted.count, rejections: rejections, moved: moved
      }
    end

    private

    # Why the row (its message id and normalized value) is rejected, or nil
    # when it applies.
    def rejection(id, value)
      return "missing message ID" if id.empty?
      return "message ID appears more than once" if id_counts[id] > 1
      return "no value: #{ACCEPTED}" if value.empty?
      return "invalid value: #{ACCEPTED}" unless value == SKIP || NewsCategory.known?(value)
      return (value == SKIP ? nil : "removed with skip") if removed_ids.include?(id)
      return "unknown message ID" unless origins.key?(id)

      "not an imported News Item" unless origins[id] == "import"
    end

    # The assigned items that have a News Copy and are changing to another
    # News Category, in row order. `assigned` is [ [ message_id, key ] ].
    def copies_to_move(assigned)
      copied = NewsItem.imported.copied.where(message_id: assigned.map(&:first))
        .pluck(:message_id, :category_key, :news_copy_message_id, :news_copy_thread_id)
        .to_h { |id, *rest| [ id, rest ] }
      assigned.filter_map do |id, key|
        previous, copy_id, thread_id = copied[id]
        next if previous.nil? || previous == key

        { message_id: id, category_key: key, previous_category_key: previous,
          news_copy: { message_id: copy_id, thread_id: thread_id } }
      end
    end

    def apply(assigned, removals)
      now = Time.current
      NewsItem.transaction do
        assigned.group_by(&:last).transform_values { |rows| rows.map(&:first) }.each do |key, ids|
          NewsItem.imported.where(message_id: ids).where("category_key IS DISTINCT FROM ?", key)
            .update_all(category_key: key, category_changed_by: @by, category_changed_at: now, updated_at: now)
        end
        fresh = removals - removed_ids.to_a
        if fresh.any?
          NewsItem.imported.where(message_id: fresh).delete_all
          NewsImportRemoval.insert_all(fresh.map { |id| { message_id: id, removed_by: @by, created_at: now } },
            unique_by: :message_id)
        end
      end
    end

    def ids = @id_list ||= @rows.map { |row| row[:message_id] }.reject(&:empty?)

    def id_counts = @id_counts ||= ids.tally

    def origins = @origins ||= NewsItem.where(message_id: ids.uniq).pluck(:message_id, :origin).to_h

    def removed_ids = @removed_ids ||= NewsImportRemoval.where(message_id: ids.uniq).pluck(:message_id).to_set
  end
end
