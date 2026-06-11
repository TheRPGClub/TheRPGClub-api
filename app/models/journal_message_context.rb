# frozen_string_literal: true

# Tracks Discord messages that carry game journal context — bot parity for
# the Oracle JOURNAL_MESSAGE_CONTEXTS table (#84). Composite PK mirrors Oracle.
class JournalMessageContext < ApplicationRecord
  self.table_name = "journal_message_contexts"
  self.primary_key = %i[channel_id message_id]

  validates :channel_id, :message_id, :created_at_ms, :owner_user_id, :game_id, presence: true
end
