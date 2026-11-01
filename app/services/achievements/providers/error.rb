# frozen_string_literal: true

module Achievements
  module Providers
    # Base class for every Provider client failure the sync engine handles.
    class Error < StandardError; end
  end
end
