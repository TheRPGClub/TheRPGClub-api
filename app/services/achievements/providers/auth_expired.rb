# frozen_string_literal: true

module Achievements
  module Providers
    # The club's own Provider credentials no longer authenticate (PSN NPSSO).
    class AuthExpired < StandardError; end
  end
end
