# frozen_string_literal: true

# A card of a member's progress grid: their cached progress on one Achievement
# Set, with the set embedded. `provider` repeats the set's Provider. Load
# records with `includes(:achievement_set)`.
class AchievementSetProgressResource
  include BaseResource
  include SetProgressFields

  attribute(:provider) { |progress| progress.achievement_set.provider }
  one :achievement_set, resource: AchievementSetResource
end
