# frozen_string_literal: true

module Achievements
  module Providers
    # The Provider has no such account, or it can no longer be linked.
    class NotFound < Error; end
  end
end
