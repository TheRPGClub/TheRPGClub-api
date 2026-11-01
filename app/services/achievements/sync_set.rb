# frozen_string_literal: true

module Achievements
  # One sync unit: imports one Achievement Set for one member, from a progress
  # row ListAccount queued (`sync_pending_at`). Ported from xergasa's
  # ImportGameAchievementsJob, split per ADR 0001 into the shared definitions
  # and the member's Unlocks and cached progress.
  #
  # In one transaction it upserts the definitions and Rarity, soft-removes
  # Achievements the Provider no longer reports (only from a non-empty list),
  # upserts the member's Unlocks, recomputes their progress and clears the
  # pending marker, then classifies the newly inserted Unlocks (Highlight and
  # announceable). An Unlock it already holds is never reclassified, so an RA
  # softcore -> hardcore upgrade is never announced again. A Provider set that
  # is missing (nil) or empty counts as no set: nothing is written but the
  # marker. Title, platform and icon come from the listing; a definition only
  # fills them when blank. A failing set is skipped without touching the
  # account (see #with_set_errors).
  class SyncSet
    include SyncUnit

    # Stored for an Unlock the Provider reports without a time (Steam
    # unlocktime 0, PSN without earnedDateTime): `unlocked_at` is required, and
    # this keeps it out of every recent feed and never announceable.
    UNKNOWN_UNLOCK_TIME = Time.at(0).utc
    ANNOUNCE_WITHIN = 48.hours

    def self.call(progress_row, now: Time.current)
      new(progress_row, now: now).call
    end

    def initialize(progress_row, now: Time.current)
      @row = progress_row
      @account = progress_row.linked_account
      @set = progress_row.achievement_set
      @now = now
    end

    def call
      cursor = @row.sync_pending_at || @now
      with_set_errors do
        definition = fetch_definition
        if definition.nil? || definition.achievements.empty?
          @row.update!(sync_pending_at: nil)
        else
          import(definition)
        end
      end
      finish_if_drained(@account, cursor: cursor, now: @now)
    end

    private

    # A failure here belongs to one title (a delisted PS title's 404, a 403 on
    # its definitions, one malformed Steam schema), never to the account: the
    # set is skipped and logged, and the account keeps syncing. The listing
    # owns account-level Private / NotFound. The set is retried when it is
    # next listed.
    def with_set_errors
      yield
    rescue *PASSED_THROUGH
      raise
    rescue StandardError => error
      Rails.logger.warn("[Achievements::SyncSet] skipped set #{@set.id} (#{@set.provider} #{@set.external_id}) " \
        "for linked account #{@account.id}: #{error.class}: #{error.message}")
      @row.update!(sync_pending_at: nil)
    end

    def fetch_definition
      client = Providers.client_for(@account.provider)
      if @set.psn?
        client.set_with_progress(@account.external_id, @set.external_id, @set.np_service_name)
      else
        client.set_with_progress(@account.external_id, @set.external_id)
      end
    end

    def import(definition)
      UserAchievementSetProgress.transaction do
        achievement_ids = upsert_definitions(definition.achievements)
        remove_unreported(achievement_ids.keys)
        update_set(definition)
        new_unlock_ids = upsert_unlocks(definition.unlocks, achievement_ids)

        progress = UserAchievementSetProgress.recompute!(user_id: @account.user_id, achievement_set_id: @set.id)
        # Steam and PSN carry no playtime here: theirs came with the listing.
        progress.update!({ sync_pending_at: nil, playtime_minutes: definition.playtime_minutes }
          .reject { |key, value| key == :playtime_minutes && value.nil? })
        classify(new_unlock_ids, progress)
      end
    end

    # external_id => achievements.id. Clears removed_at on any that reappear.
    def upsert_definitions(definitions)
      rows = definitions.uniq(&:external_id).map do |achievement|
        achievement.to_h.merge(achievement_set_id: @set.id, removed_at: nil)
      end
      Achievement.upsert_all(rows, unique_by: %i[achievement_set_id external_id],
        update_only: rows.first.keys - %i[achievement_set_id external_id])
      @set.achievements.where(external_id: rows.pluck(:external_id)).pluck(:external_id, :id).to_h
    end

    def remove_unreported(reported_external_ids)
      return if reported_external_ids.empty?

      @set.achievements.active.where.not(external_id: reported_external_ids).update_all(removed_at: @now)
    end

    def update_set(definition)
      active = @set.achievements.active
      attributes = { achievements_count: active.count, points_total: active.sum(:points), definitions_synced_at: @now }
      %i[title platform_label icon_url].each do |column|
        attributes[column] = definition.public_send(column) if @set[column].blank? && definition.public_send(column)
      end
      @set.update!(attributes)
    end

    # Inserts the member's new Unlocks and updates the ones they already hold
    # (time, hardcore). Returns the inserted ids.
    def upsert_unlocks(provider_unlocks, achievement_ids)
      provider_unlocks = provider_unlocks.uniq(&:achievement_external_id)
        .select { |unlock| achievement_ids.key?(unlock.achievement_external_id) }
      held = UserAchievementUnlock.where(user_id: @account.user_id, achievement_id: achievement_ids.values)
        .index_by(&:achievement_id)

      new_rows = provider_unlocks.filter_map do |unlock|
        achievement_id = achievement_ids.fetch(unlock.achievement_external_id)
        if (existing = held[achievement_id])
          refresh_unlock(existing, unlock)
          next
        end

        {
          user_id: @account.user_id,
          achievement_id: achievement_id,
          user_linked_account_id: @account.id,
          unlocked_at: unlock.unlocked_at || UNKNOWN_UNLOCK_TIME,
          hardcore: unlock.hardcore?,
          hardcore_unlocked_at: unlock.hardcore_unlocked_at,
          announceable: false
        }
      end
      return [] if new_rows.empty?

      UserAchievementUnlock.insert_all(new_rows, unique_by: %i[user_id achievement_id], returning: %i[id])
        .rows.flatten
    end

    def refresh_unlock(existing, unlock)
      existing.assign_attributes(hardcore: unlock.hardcore?, hardcore_unlocked_at: unlock.hardcore_unlocked_at,
        user_linked_account_id: @account.id)
      existing.unlocked_at = unlock.unlocked_at if unlock.unlocked_at
      existing.save! if existing.changed?
    end

    # Only one new Unlock may be the set's Completion / Mastery: when several
    # share the completing time, the highest display_order takes it and the
    # others fall back to rare or nothing.
    def classify(new_unlock_ids, progress)
      return if new_unlock_ids.empty?

      unlocks = UserAchievementUnlock.where(id: new_unlock_ids).includes(achievement: :achievement_set).to_a
      completer = unlocks.select do |unlock|
        (progress.completed_at && unlock.unlocked_at == progress.completed_at) ||
          (progress.mastered_at && unlock.hardcore? && unlock.mastery_time == progress.mastered_at)
      end
        .max_by { |unlock| [ unlock.achievement.display_order || -1, unlock.id ] }
      no_completion = UserAchievementSetProgress.new

      unlocks.each do |unlock|
        highlight = UserAchievementUnlock.classify_highlight(unlock,
          progress_after: unlock.equal?(completer) ? progress : no_completion)
        next unless highlight

        unlock.update_columns(highlight: highlight, announceable: announceable?(unlock), updated_at: @now)
      end
    end

    # Highlights are announced only when found by an incremental sync (never a
    # Backfill) within 48h of the Unlock.
    def announceable?(unlock)
      @account.incremental? && unlock.unlocked_at >= @now - ANNOUNCE_WITHIN
    end
  end
end
