# frozen_string_literal: true

module Achievements
  module Providers
    # The Provider is throttling the club. retry_after is the Provider's
    # Retry-After in seconds (nil when it sent none), so the caller can back off.
    class RateLimited < StandardError
      attr_reader :retry_after

      def initialize(message = "Provider is rate limiting requests.", retry_after: nil)
        @retry_after = retry_after
        super(message)
      end
    end
  end
end
