# frozen_string_literal: true

module Achievements
  module Providers
    # The Provider has no such user (or the Linked Account's identity is gone).
    class NotFound < Error; end
  end
end
