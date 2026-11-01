# frozen_string_literal: true

# An Achievement definition, shared by every member (ADR 0001). `removed_at` is
# set once the Provider stopped reporting it.
class AchievementResource
  include BaseResource
  include AchievementFields
end
