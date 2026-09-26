# frozen_string_literal: true

module Voting
  # Scheduled every minute in config/recurring.yml.
  class AdvanceRoundsJob < ApplicationJob
    queue_as :default

    def perform
      Voting::AdvanceRounds.call
    end
  end
end
