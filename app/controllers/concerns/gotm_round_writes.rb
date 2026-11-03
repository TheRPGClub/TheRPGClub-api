# frozen_string_literal: true

# The round-level create, the per-game writes and the bot cache reload
# shared by the GOTM and NR-GOTM entry controllers (#331). Staff writes queue
# gotm_cache_reload; the service's do not, since the bot made them. The including controller defines
# `round_category` ("gotm" or "nr_gotm") and `entry_resource`.
module GotmRoundWrites
  extend ActiveSupport::Concern

  # POST /api/v1/(nr_)gotm_entries/rounds
  # { data: { round_number, month_year, games: [{ gamedb_game_id, reddit_url? }] } }
  def create_round
    data = request_data
    entries = ActiveRecord::Base.transaction do
      created = Gotm::RoundCreate.new(
        category: round_category, round_number: data[:round_number], month_year: data[:month_year],
        games: data[:games]
      ).call!
      enqueue_cache_reload(created.first, "round added")
      created
    end
    # Same side effects as a per-game create (see #create).
    Voting::LegacySync.winner_recorded(entries.first.round_number)
    Gamedb::GameRelationsCacheVersion.bump!
    render json: { data: entries.map { |e| entry_resource.new(e).serializable_hash } }, status: :created
  rescue Gotm::RoundCreate::Invalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  # Payload (kind gotm_cache_reload): { category, round_number }. The bot
  # reloads that round from the API. Not queued for the service's per-entry
  # writes: the bot updates its own cache when it makes them.
  def enqueue_cache_reload(entry, what)
    BotJob.enqueue!(
      kind: "gotm_cache_reload",
      summary: "Reload #{Gotm::RoundCreate.label(round_category)} round #{entry.round_number} " \
               "(#{entry.month_year}) in the bot: #{what}",
      payload: { category: round_category, round_number: entry.round_number },
      requested_by: current_principal.discord_user? ? current_principal.id : nil
    )
  end

  # A per-game create. The bot's round-setup wizard recording winners
  # decides the round. GameResource's (nr_)gotm_won is a live EXISTS
  # subquery, but GamesController#relations_data caches it on an alternate
  # game's behalf without touching that game, so bump the shared version.
  def create_entry(model)
    entry = model.transaction do
      created = model.create!(request_data.slice(*self.class::CREATE_ATTRS))
      enqueue_cache_reload(created, "game #{created.game_index + 1} added") if current_principal.discord_user?
      created
    end
    entry.reload
    Voting::LegacySync.winner_recorded(entry.round_number)
    Gamedb::GameRelationsCacheVersion.bump!
    render json: { data: entry_resource.new(entry).serializable_hash }, status: :created
  end

  # A per-game delete; staff deletes reload the bot's cache too.
  def destroy_entry(entry)
    entry.transaction do
      entry.destroy!
      enqueue_cache_reload(entry, "game #{entry.game_index + 1} removed") if current_principal.discord_user?
    end
    Gamedb::GameRelationsCacheVersion.bump!
    render json: { deleted: true }
  end

  # A per-entry update by staff (not the bot's own service writes).
  def update_entry(entry)
    entry.transaction do
      entry.update!(request_data.slice(*self.class::UPDATE_ATTRS))
      enqueue_cache_reload(entry, "game #{entry.game_index + 1} edited") if current_principal.discord_user?
    end
    entry.reload
    Gamedb::GameRelationsCacheVersion.bump!
    render json: { data: entry_resource.new(entry).serializable_hash }
  end
end
