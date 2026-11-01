# frozen_string_literal: true

module Achievements
  module Providers
    # Base class for the failures every Provider client reports in the same
    # terms, so the sync units can react without knowing the Provider.
    class Error < StandardError; end
  end
end
