# frozen_string_literal: true

# A member's cached progress on one Achievement Set, without the set (the set
# page and the game showcase already carry it).
class SetProgressResource
  include BaseResource
  include SetProgressFields
end
