# frozen_string_literal: true

namespace :voting do
  desc "Run one round-lifecycle sweep (Voting::AdvanceRounds); needs VOTING_AUTOMATION_ENABLED=true"
  task advance: :environment do
    Voting::AdvanceRounds.call
  end
end
