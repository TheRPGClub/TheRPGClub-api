# frozen_string_literal: true

# Suggests what a member should play next from their backlog and/or collection
# (the bot's `/backlog pick`, web-parity #286). Ports
# `bot/src/commands/backlog/backlog-pick.service.ts`:
#
# - Candidates are the user's backlog rows (`source=backlog`, the default), the
#   collection rows (`collection`) or both, minus games already on Now Playing.
#   A `platform_id` filter is an exact match, so entries without a platform drop
#   out. A game in both lists counts once, as its backlog entry. Unlike the bot
#   there is no 200-row cap.
# - Selection is uniform: the candidates are stably ordered (backlog before
#   collection, then entry_id), shuffled with `Random.new(seed)`, and walked from
#   `position`, wrapping once. The same seed and position give the same pick, so
#   clients reroll statelessly with `position = next_position`. The shuffle does
#   not reproduce the bot's mulberry32 sequence; that only matters if the bot
#   moves onto this endpoint.
# - With `max_hours`, a candidate qualifies only when its HLTB time (main, then
#   single player, then main + sides) is at most `max_hours`. Games without an
#   HLTB time are skipped. The HLTB cache is read in one query, not per candidate.
class BacklogPicker
  SOURCES = %w[backlog collection both].freeze
  MAX_SEED = 0xffffffff

  Candidate = Data.define(:kind, :entry_id, :gamedb_game_id, :platform_id)
  Pick = Data.define(:kind, :entry, :hltb, :hours)
  Result = Data.define(:pick, :position, :next_position, :wrapped, :total, :platforms)

  # HowLongToBeat strings are like "12 Hours", "12½ Hours" or "30 Mins".
  # Placeholders ("--") and zero read as no time. Mirrors the bot's
  # `parseHltbHours`.
  def self.parse_hours(value)
    return nil if value.blank?

    text = value.gsub("½", ".5").downcase
    match = text.match(/\d+(?:\.\d+)?|\.\d+/)
    return nil unless match

    amount = match[0].to_f
    return nil unless amount.positive?

    text.include?("min") ? amount / 60 : amount
  end

  def self.hours_for(hltb)
    return nil unless hltb

    parse_hours(hltb.main) || parse_hours(hltb.single_player) || parse_hours(hltb.main_sides)
  end

  def initialize(user_id:, seed:, source: "backlog", platform_id: nil, max_hours: nil, position: 0)
    @user_id = user_id
    @seed = seed
    @source = source
    @platform_id = platform_id
    @max_hours = max_hours
    @position = position
  end

  def call
    rows = source_rows
    platforms = platform_options(rows)
    rows = rows.select { |row| row.platform_id == @platform_id } if @platform_id
    order = shuffle(dedupe(rows))
    hit = walk(order)

    Result.new(
      pick: hit && build_pick(hit[:candidate], hit[:hltb], hit[:hours]),
      position: hit&.fetch(:position),
      next_position: hit && hit[:position] + 1,
      wrapped: hit ? hit[:wrapped] : false,
      total: order.size,
      platforms: platforms
    )
  end

  private

  # Backlog rows first (in the bot's list order), then collection rows, so the
  # dedupe keeps the backlog entry for a game in both.
  def source_rows
    rows = []
    rows.concat(candidates_from(UserGameBacklog, "backlog", sort_order: :asc, created_at: :desc)) unless @source == "collection"
    rows.concat(candidates_from(UserGameCollection, "collection", created_at: :desc)) unless @source == "backlog"
    rows
  end

  def candidates_from(model, kind, order)
    now_playing = UserNowPlaying.where(user_id: @user_id).where.not(gamedb_game_id: nil).select(:gamedb_game_id)
    model.where(user_id: @user_id).where.not(gamedb_game_id: now_playing).order(order)
      .pluck(:entry_id, :gamedb_game_id, :platform_id)
      .map { |entry_id, game_id, platform_id| Candidate.new(kind, entry_id, game_id, platform_id) }
  end

  def dedupe(rows)
    rows.uniq(&:gamedb_game_id)
  end

  def shuffle(candidates)
    candidates
      .sort_by { |c| [ c.kind == "backlog" ? 0 : 1, c.entry_id ] }
      .shuffle(random: Random.new(@seed))
  end

  # Walks the shuffled order from the requested position, wrapping once, and
  # returns the first candidate that passes the HLTB filter.
  def walk(order)
    total = order.size
    return nil if total.zero?

    hltb = RpgClubHltbCache.where(gamedb_game_id: order.map(&:gamedb_game_id)).index_by(&:gamedb_game_id)
    total.times do |offset|
      raw = @position + offset
      candidate = order[raw % total]
      cache = hltb[candidate.gamedb_game_id]
      hours = self.class.hours_for(cache)
      next if @max_hours && (hours.nil? || hours > @max_hours)

      return { candidate:, hltb: cache, hours:, position: raw % total, wrapped: raw >= total }
    end
    nil
  end

  def build_pick(candidate, hltb, hours)
    model = candidate.kind == "backlog" ? UserGameBacklog : UserGameCollection
    entry = model.includes(:game, :platform).find(candidate.entry_id)
    Pick.new(candidate.kind, entry, hltb, hours)
  end

  # The platforms the filter can choose from: every platform among the
  # candidates before the platform filter, with how many distinct games each
  # would offer. Entries without a platform can't be filtered to, so they're left out.
  def platform_options(rows)
    counts = rows.reject { |r| r.platform_id.nil? }.group_by(&:platform_id)
      .transform_values { |group| group.map(&:gamedb_game_id).uniq.size }
    return [] if counts.empty?

    GamedbPlatform.where(platform_id: counts.keys).map do |platform|
      {
        "platform_id" => platform.platform_id,
        "platform_name" => platform.platform_name,
        "platform_abbreviation" => platform.platform_abbreviation,
        "count" => counts.fetch(platform.platform_id)
      }
    end.sort_by { |p| [ -p["count"], p["platform_name"].to_s.downcase, p["platform_id"] ] }
  end
end
