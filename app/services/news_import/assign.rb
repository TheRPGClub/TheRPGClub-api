# frozen_string_literal: true

module NewsImport
  # Applies a reviewed list of (message id, value) rows to imported News
  # Items (spec #355, ticket #359). A News Category key assigns that News
  # Category, which makes the item visible to members; `skip` deletes the
  # item and remembers the removal (NewsImportRemoval). Values ignore case
  # and surrounding spaces. Assigning again changes the News Category, and
  # `skip` for an item already removed counts as removed again, so the same
  # file can be applied twice.
  #
  # Each bad row is rejected with a reason and does not stop the others:
  # a missing or repeated message id, a blank or invalid value, a message id
  # with no News Item, a live (not imported) News Item, or a category for an
  # item removed with `skip`.
  #
  # Returns { assigned:, removed:, rejected:, unsorted:, rejections: [ { index, message_id, value, reason } ] },
  # where `unsorted` is how many imported News Items are still unsorted afterwards.
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

      assignments = Hash.new { |hash, key| hash[key] = [] }
      removals = []
      rejections = []
      @rows.each_with_index do |row, index|
        value = row[:value].strip.downcase
        if (reason = rejection(row[:message_id], value))
          rejections << { index: index, message_id: row[:message_id], value: row[:value], reason: reason }
        elsif value == SKIP
          removals << row[:message_id]
        else
          assignments[value] << row[:message_id]
        end
      end

      apply(assignments, removals)
      {
        assigned: assignments.values.sum(&:size), removed: removals.size, rejected: rejections.size,
        unsorted: NewsItem.unsorted.count, rejections: rejections
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

    def apply(assignments, removals)
      now = Time.current
      NewsItem.transaction do
        assignments.each do |key, ids|
          NewsItem.imported.where(message_id: ids).update_all(category_key: key, updated_at: now)
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
