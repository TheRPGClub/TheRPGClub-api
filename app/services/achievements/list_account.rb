# frozen_string_literal: true

module Achievements
  # One sync unit: lists a Linked Account's played Achievement Sets and queues
  # each changed set for an import (SyncSet), through durable Postgres state
  # (ADR 0003). A Backfill lists every played set; an incremental sync only
  # those with Provider activity since `last_synced_at`. Ported from xergasa's
  # ImportLibraryJob, made per-member.
  #
  # Upserts the shared `achievement_sets` (title, platform and icon come from
  # the listing: Steam and PSN definitions carry none) and one progress row per
  # set with `sync_pending_at`; a new set gets a placeholder row (`synced_at`
  # nil). Listed playtime (Steam) is stored on the progress row. Clears
  # `sync_due_at`.
  #
  # PSN's Playtime comes from the member's play history (spec api#457, spike
  # api#462), read here, so once per account per Sync Window with no job of
  # its own. Both reads happen before any write: a RateLimited or
  # AuthExpired leaves the listing due for the tick to retry whole. Any other
  # play-history failure is logged and the listing goes on without it.
  class ListAccount
    include SyncUnit

    def self.call(account, now: Time.current)
      new(account, now: now).call
    end

    def initialize(account, now: Time.current)
      @account = account
      @now = now
    end

    def call
      with_sync_errors(@account) do
        since = @account.incremental? ? @account.last_synced_at : nil
        client = Providers.client_for(@account.provider)
        played_sets = client.played_sets(@account.external_id, since: since)
        played_minutes = psn_playtime(client)

        new_set_ids = UserLinkedAccount.transaction do
          @account.update!(sync_due_at: nil)
          new_ids = queue_sets(played_sets.uniq(&:external_id))
          write_playtime(played_minutes)
          new_ids
        end
        link_new_sets(new_set_ids)
        finish_if_drained(@account, cursor: @now, now: @now)
      end
    end

    private

    # Returns the ids of the sets this listing created.
    def queue_sets(played_sets)
      return [] if played_sets.empty?

      known_ids = AchievementSet.where(provider: @account.provider, external_id: played_sets.map(&:external_id)).ids
      set_ids = upsert_sets(played_sets)
      with_playtime, without_playtime = played_sets.partition(&:playtime_minutes)
      upsert_progress(with_playtime, set_ids, playtime: true)
      upsert_progress(without_playtime, set_ids, playtime: false)
      set_ids.values - known_ids
    end

    # upsert_all skips AchievementSet's after_create_commit, so the GameDB link
    # (best-effort) is enqueued here, once the sets are committed.
    def link_new_sets(set_ids)
      return if set_ids.empty?

      ActiveJob.perform_all_later(AchievementSet.where(id: set_ids).map { |set| LinkSetToGameJob.new(set) })
    end

    # external_id => achievement_sets.id
    def upsert_sets(played_sets)
      rows = played_sets.map do |set|
        {
          provider: @account.provider,
          external_id: set.external_id,
          title: set.title,
          platform_label: set.platform_label,
          icon_url: set.icon_url,
          np_service_name: set.np_service_name
        }
      end
      AchievementSet.upsert_all(rows, unique_by: %i[provider external_id],
        update_only: %i[title platform_label icon_url np_service_name])
      AchievementSet.where(provider: @account.provider, external_id: played_sets.map(&:external_id))
        .pluck(:external_id, :id).to_h
    end

    def upsert_progress(played_sets, set_ids, playtime:)
      return if played_sets.empty?

      rows = played_sets.map do |set|
        row = {
          user_id: @account.user_id,
          achievement_set_id: set_ids.fetch(set.external_id),
          user_linked_account_id: @account.id,
          sync_pending_at: @now
        }
        playtime ? row.merge(playtime_minutes: set.playtime_minutes) : row
      end
      update_only = %i[user_linked_account_id sync_pending_at]
      update_only << :playtime_minutes if playtime
      UserAchievementSetProgress.upsert_all(rows, unique_by: %i[user_id achievement_set_id], update_only: update_only)
    end

    # npCommunicationId => minutes, adding up the titles (PS4 and PS5
    # editions) that share a trophy list. Empty for other Providers, a hidden
    # or empty history, or a failed read.
    def psn_playtime(client)
      return {} unless @account.provider == "psn"

      client.played_games(@account.external_id).each_with_object(Hash.new(0)) do |game, minutes|
        minutes[game.external_id] += game.minutes
      end
    rescue *PASSED_THROUGH
      raise
    rescue Providers::Error => error
      Rails.logger.warn("[ListAccount] PSN play history skipped for account #{@account.id}: #{error.message}")
      {}
    end

    # Onto this account's progress rows only; a set the history doesn't list
    # keeps what it had.
    def write_playtime(minutes_by_set)
      return if minutes_by_set.empty?

      set_ids = AchievementSet.where(provider: @account.provider, external_id: minutes_by_set.keys).pluck(:external_id, :id)
      set_ids.group_by { |external_id, _id| minutes_by_set.fetch(external_id) }.each do |minutes, sets|
        @account.set_progress.where(achievement_set_id: sets.map(&:last))
          .where("playtime_minutes IS DISTINCT FROM ?", minutes)
          .update_all(playtime_minutes: minutes, updated_at: @now)
      end
    end

    def clear_unit_marker
      @account.update!(sync_due_at: nil)
    end
  end
end
