# frozen_string_literal: true

module Achievements
  # Links a newly created Achievement Set to its GameDB game. Enqueued by
  # AchievementSet's after_create_commit, so it only runs while a sync is
  # creating sets. Linking is best-effort and must never block sync.
  class LinkSetToGameJob < ApplicationJob
    include CpuLogging

    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(set)
      LinkSetToGame.call(set)
    end
  end
end
