# frozen_string_literal: true

module NewsImport
  # Records one batch of the Game News Archive's messages as imported News
  # Items (spec #355, ticket #359). Safe to repeat: items are matched by
  # message id, an item staff already sorted keeps its News Category, and a
  # message staff removed with `skip` is never brought back. Each message
  # stands alone: an invalid one is rejected with a reason and the rest are
  # still recorded.
  #
  # Returns { created:, updated:, previously_removed:, rejected: [ { index, message_id, reason } ] }.
  class RecordBatch
    MAX_ITEMS = 100

    class TooLarge < StandardError; end

    def self.call(items) = new(items).call

    def initialize(items)
      @items = items
    end

    def call
      raise TooLarge, "at most #{MAX_ITEMS} items per batch" if @items.size > MAX_ITEMS

      result = { created: 0, updated: 0, previously_removed: 0, rejected: [] }
      live = live_message_ids
      removed = removed_message_ids
      @items.each_with_index do |attrs, index|
        message_id = attrs["message_id"].presence&.to_s
        if removed.include?(message_id)
          result[:previously_removed] += 1
          next
        end
        if live.include?(message_id)
          result[:rejected] << { index: index, message_id: message_id, reason: "already recorded as a live News Item" }
          next
        end

        _item, created = NewsItem.record!(message_id, attrs.except("message_id"), origin: "import")
        result[created ? :created : :updated] += 1
      rescue ActiveRecord::RecordInvalid => error
        result[:rejected] << { index: index, message_id: message_id, reason: error.record.errors.full_messages.join(", ") }
      end
      result
    end

    private

    def message_ids = @items.filter_map { |attrs| attrs["message_id"].presence&.to_s }

    def live_message_ids = NewsItem.where(message_id: message_ids, origin: "live").pluck(:message_id).to_set

    def removed_message_ids = NewsImportRemoval.where(message_id: message_ids).pluck(:message_id).to_set
  end
end
