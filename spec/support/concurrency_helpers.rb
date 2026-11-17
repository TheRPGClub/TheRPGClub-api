# frozen_string_literal: true

# For specs that race two transactions (tagged `use_transactional_tests =
# false`, so each thread sees the others' commits).
module ConcurrencyHelpers
  # Runs the block in a thread on its own database connection; its result
  # or error comes back from Thread#value.
  def in_thread(&block)
    Thread.new do
      Thread.current.report_on_exception = false
      ActiveRecord::Base.connection_pool.with_connection(&block)
    end
  end

  # Waits until some transaction is blocked waiting for a lock.
  def wait_for_a_blocked_lock(timeout: 2.5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until ActiveRecord::Base.connection.select_value("SELECT count(*) FROM pg_locks WHERE NOT granted").positive?
      raise "nothing waited on a lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end
end

RSpec.configure { |config| config.include ConcurrencyHelpers }
