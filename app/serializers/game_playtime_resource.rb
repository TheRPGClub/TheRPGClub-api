# frozen_string_literal: true

# A member's Playtime for one game (Playtime::Ledger::GamePlaytime): the
# total, the breakdown and the mismatches. Each platform comes with its GameDB
# name from `params[:platform_names]` ({ platform_id => name }); a Provider
# set whose label didn't resolve has a null `platform_id` and keeps its raw
# `platform_label`. `open_playthrough` is null until Playthroughs (api#459).
class GamePlaytimeResource
  include BaseResource

  attributes :user_id, :game_id, :total_minutes

  attribute :breakdown do |playtime|
    names = params[:platform_names]
    {
      provider_sets: playtime.provider_sets.map do |set|
        set.to_h.slice(:achievement_set_id, :provider, :title, :platform_label, :platform_id)
          .merge(platform_name: names[set.platform_id], minutes: set.minutes, counted: set.counted)
      end,
      manual_entries: playtime.manual_entries.map do |entry|
        entry.to_h.merge(platform_name: names[entry.platform_id])
      end
    }
  end

  attribute :mismatches do |playtime|
    playtime.mismatches.map do |mismatch|
      mismatch.to_h.slice(:platform_id).merge(platform_name: params[:platform_names][mismatch.platform_id])
        .merge(mismatch.to_h.except(:platform_id))
    end
  end

  attribute :open_playthrough, &:open_playthrough
end
