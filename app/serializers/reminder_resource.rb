# frozen_string_literal: true

# Serializes a UserReminder (all columns). The bot delivery columns
# (`sent_at`, `failure_count`, `failed_at`) are exposed read-only so a client
# can see delivery state — the controller strips them from writes (#41).
class ReminderResource
  include BaseResource

  columns_of UserReminder
end
