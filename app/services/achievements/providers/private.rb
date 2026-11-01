# frozen_string_literal: true

module Achievements
  module Providers
    # The Provider hides this user's achievements. Never read as zero Unlocks.
    class Private < Error; end
  end
end
