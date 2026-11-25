# frozen_string_literal: true

# Each example starts with the due feed's gate open, as a fresh machine does.
RSpec.configure do |config|
  config.before { Gamedb::DueAnnouncementGate.clear }
end
