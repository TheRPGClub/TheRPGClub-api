# frozen_string_literal: true

# Serializes a BotPresenceHistory row. The surrogate `id` is internal-only, so
# the response exposes just the four logical columns the bot consumes:
# `activity_name`, `set_at`, `set_by_user_id`, `set_by_username` (#94).
class BotPresenceResource
  include BaseResource

  columns_of BotPresenceHistory, except: %w[id]
end
