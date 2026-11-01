# frozen_string_literal: true

module Achievements
  module Providers
    # The account exists but hides its achievements from the club.
    # Never read as zero Unlocks.
    class Private < Error; end
  end
end
