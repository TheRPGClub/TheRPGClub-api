# frozen_string_literal: true

module Achievements
  module Providers
    # The account exists but hides its achievements from the club.
    class Private < StandardError; end
  end
end
