# frozen_string_literal: true

require "webmock/rspec"

# Provider clients never hit the network in specs: every outbound HTTP call
# must be stubbed. Localhost stays open for the test database and Rails.
WebMock.disable_net_connect!(allow_localhost: true)
