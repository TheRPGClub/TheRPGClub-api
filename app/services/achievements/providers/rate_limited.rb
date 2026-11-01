# frozen_string_literal: true

module Achievements
  module Providers
    # The Provider is throttling us. `retry_after` is in seconds, nil when unknown.
    class RateLimited < Error
      attr_reader :retry_after

      def initialize(message = "Provider is rate limiting requests.", retry_after: nil)
        @retry_after = retry_after
        super(message)
      end
    end
  end
end
