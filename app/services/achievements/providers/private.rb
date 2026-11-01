# frozen_string_literal: true

module Achievements
  module Providers
    # The member's profile or achievements are hidden; pause the Linked Account, never treat it as zero Unlocks.
    class Private < Error; end
  end
end
