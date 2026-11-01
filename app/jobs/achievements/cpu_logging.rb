# frozen_string_literal: true

module Achievements
  # Logs each hub job's CPU cost as `[JobCPU] <Job> cpu_ms=<n>` (ported from
  # xergasa's ApplicationJob, scoped to the Achievement Hub jobs). Sync runs
  # inside Puma on the app machine (ADR 0003); these lines are the trigger for
  # revisiting a separate worker if sync starts starving API requests.
  module CpuLogging
    extend ActiveSupport::Concern

    # Process CPU time where the platform has it (production is Linux), wall
    # time otherwise.
    CPU_CLOCK = defined?(Process::CLOCK_PROCESS_CPUTIME_ID) ? Process::CLOCK_PROCESS_CPUTIME_ID : Process::CLOCK_MONOTONIC

    included do
      around_perform do |job, block|
        cpu_before = Process.clock_gettime(CPU_CLOCK)
        block.call
      ensure
        cpu_ms = ((Process.clock_gettime(CPU_CLOCK) - cpu_before) * 1000).round
        Rails.logger.info("[JobCPU] #{job.class.name} cpu_ms=#{cpu_ms}")
      end
    end
  end
end
