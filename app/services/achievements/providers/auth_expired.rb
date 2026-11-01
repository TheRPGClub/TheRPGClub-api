# frozen_string_literal: true

module Achievements
  module Providers
    # The club's own Provider credentials (PSN NPSSO) no longer authenticate.
    class AuthExpired < Error; end
  end
end
