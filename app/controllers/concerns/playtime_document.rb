# frozen_string_literal: true

# Renders a member's Playtime for one game (Playtime::Ledger), with their open
# and earlier Playthroughs, as the playtime endpoints answer it, and the write
# gate they share: the member's own, or a Superadmin's (and the bot's) for
# anyone, as with Completions.
module PlaytimeDocument
  extend ActiveSupport::Concern

  private

  def render_playtime(user_id, game_id, status: :ok)
    playtime = Playtime::Ledger.for_game(user_id: user_id, game_id: game_id)
    playthroughs = UserGamePlaythrough.ended.where(user_id: user_id, gamedb_game_id: game_id)
      .order(ended_at: :desc, id: :desc).to_a
    render json: { data: GamePlaytimeResource.new(playtime, params: { platform_names: platform_names(playtime),
      playthroughs: playthroughs }).serializable_hash }, status: status
  end

  def platform_names(playtime)
    ids = (playtime.provider_sets + playtime.manual_entries).filter_map(&:platform_id).uniq
    ids.empty? ? {} : GamedbPlatform.where(platform_id: ids).pluck(:platform_id, :platform_name).to_h
  end

  def require_owner_or_superadmin!
    return true if current_principal&.discord_user? && superadmin?

    require_owner!
  end
end
