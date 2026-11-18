# frozen_string_literal: true

module ClubCodex
  # The Daily Fun Fact (GLOSSARY.md, "Daily Fun Fact"; ticket #406),
  # scheduled at 15:00 America/New_York in config/recurring.yml. Draws the
  # next Fun Fact from the queue /funfact uses (FunFactQueue) and queues one
  # `daily_fun_fact` bot job with the club date and the entry id, or nothing
  # on a day with no Fun Facts.
  #
  # One post per club day: the DailyFunFactPost row is written with the draw
  # and the bot job, in one transaction, so a re-run the same day posts
  # nothing new and a run that fails to queue leaves the queue where it was.
  # While the Club Codex is Off the run is skipped and the queue doesn't move.
  class DailyFunFactJob < ApplicationJob
    queue_as :default

    KIND = "daily_fun_fact"
    FEATURE_KEY = "club_codex"

    def perform
      return if Features.off?(FEATURE_KEY)

      now = Time.current
      club_date = Challenges.today(now)
      DailyFunFactPost.transaction do
        next if DailyFunFactPost.exists?(club_date: club_date)

        entry = FunFactQueue.draw!(at: now)
        post(entry, club_date) if entry
      end
    end

    private

    # Records the day's post and queues it. A racing run that recorded the
    # day first wins: this one rolls back, its draw included.
    def post(entry, club_date)
      written = DailyFunFactPost.insert_all([ { club_date: club_date, entry_id: entry.id } ],
        unique_by: :ux_daily_fun_fact_posts_club_date, returning: %i[id])
      raise ActiveRecord::Rollback if written.empty?

      BotJob.enqueue!(kind: KIND, summary: "Daily Fun Fact ##{entry.id} for #{club_date.iso8601}",
        payload: { club_date: club_date.iso8601, entry_id: entry.id })
    end
  end
end
