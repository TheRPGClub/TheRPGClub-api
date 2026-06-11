# frozen_string_literal: true

# Serializes a JournalMessageContext (all columns) — #84.
class JournalMessageContextResource
  include BaseResource

  columns_of JournalMessageContext
end
