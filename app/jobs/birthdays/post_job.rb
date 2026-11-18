# frozen_string_literal: true

module Birthdays
  # The Birthday Post (GLOSSARY.md, "Birthday Post"; ticket #401), scheduled
  # at 10:00 America/New_York in config/recurring.yml. Queues one
  # `birthday_post` bot job greeting every member still in the server whose
  # shared Birthday it is today (Birthdays.falling_on), or nothing on a day
  # with none. The job names the channel to post in, general chat
  # (DiscordChannels::GENERAL), so the API owns where the post goes.
  #
  # A member gets at most one Birthday Post a calendar year: a BirthdayPost row
  # per member and year is written with the bot job, in one transaction, and a
  # member who already has this year's is left out, so a re-run (or a Birth
  # Date moved to a later day) queues nothing new for them.
  #
  # It runs once a day and a missed run is not retried (owner decision,
  # 2026-11-18): if the API is down or redeploying at 10:00 New York time,
  # Solid Queue doesn't backfill the tick and its machine-local queue loses
  # anything not yet performed, so that day's members are not greeted and
  # are greeted next year instead. Likewise a member who starts sharing after
  # 10:00 on their Birthday waits for next year. The bot being down is
  # covered: the bot job waits in Postgres and the bot posts it later the same
  # club day.
  #
  # Birthdays are not a Feature: `birthday_post` is in neither
  # BotJob::PUBLIC_POST_FEATURES nor FEATURE_WORK, so it carries no
  # `feature_key` and no Feature Flag gates it.
  class PostJob < ApplicationJob
    queue_as :default

    KIND = "birthday_post"

    def perform
      # The club day the job runs on, not the cron tick's: a worker stalled
      # past midnight would greet the next day's members (very unlikely).
      today = ClubDay.today
      BirthdayPost.transaction do
        greeted = record_posts(due(today), today)
        enqueue(greeted, today) if greeted.any?
      end
    end

    private

    # The members due a Birthday Post today, in the order Upcoming Birthdays
    # lists them (Members.by_name), so the bot greets them in a stable,
    # readable order. A day has few Birthdays, so they are sorted in Ruby.
    def due(today)
      already_posted = BirthdayPost.where(year: today.year).where("birthday_posts.user_id = rpg_club_users.user_id")
      Birthdays.falling_on(today, RpgClubUser.active.where(birthday_shared: true))
        .where.not(already_posted.arel.exists)
        .select(:user_id, :global_name, :username)
        .sort_by { |user| Members.by_name(user) }
        .map(&:user_id)
    end

    # Writes this year's BirthdayPost for each of `user_ids`, skipping any a
    # racing run already wrote, and returns the members it wrote, in order.
    def record_posts(user_ids, today)
      return [] if user_ids.empty?

      rows = user_ids.map { |user_id| { user_id: user_id, year: today.year, posted_on: today } }
      written = BirthdayPost.insert_all(rows, unique_by: :ux_birthday_posts_once, returning: %i[user_id]).rows.flatten
      user_ids & written
    end

    def enqueue(user_ids, today)
      BotJob.enqueue!(kind: KIND,
        summary: "Birthday Post for #{user_ids.size} #{'member'.pluralize(user_ids.size)} on #{today.iso8601}",
        payload: { club_date: today.iso8601, user_ids: user_ids, channel_id: DiscordChannels::GENERAL })
    end
  end
end
