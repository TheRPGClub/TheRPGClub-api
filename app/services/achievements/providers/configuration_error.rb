# frozen_string_literal: true

module Achievements
  module Providers
    # A Provider client is missing its configuration (e.g. no API key). Not an
    # account error: the sync units re-raise it and leave the sync state
    # untouched, so the accounts sync once the deploy is fixed.
    class ConfigurationError < StandardError; end
  end
end
