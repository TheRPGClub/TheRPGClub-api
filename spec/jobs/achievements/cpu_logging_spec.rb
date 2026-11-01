# frozen_string_literal: true

require "rails_helper"

RSpec.describe Achievements::CpuLogging do
  it "logs each hub job's CPU cost" do
    allow(Rails.logger).to receive(:info)

    Achievements::ProviderTickJob.perform_now("steam")

    expect(Rails.logger).to have_received(:info).with(/\A\[JobCPU\] Achievements::ProviderTickJob cpu_ms=\d+\z/)
  end

  it "logs even when the job raises" do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(UserAchievementSetProgress).to receive(:sync_pending).and_raise(Steam::Client::ConfigurationError)

    expect { Achievements::ProviderTickJob.perform_now("steam") }.to raise_error(Steam::Client::ConfigurationError)
    expect(Rails.logger).to have_received(:info).with(/\[JobCPU\] Achievements::ProviderTickJob/)
  end

  it "is scoped to the hub jobs" do
    expect(ApplicationJob.ancestors).not_to include(described_class)
    expect([ Achievements::ProviderTickJob, Achievements::SyncWindowJob, Achievements::LinkSetToGameJob ])
      .to all(include(described_class))
  end
end
