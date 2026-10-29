# frozen_string_literal: true

module Imports
  # Resolves a free-text platform label from an import row to a
  # gamedb_platforms.platform_id, ported from the bot.
  #
  # - #resolve(raw): the collection CSV rule (resolveCsvPlatformId). Look the
  #   label up in PLATFORM_MAP (config/import_platform_map.yml); try each
  #   mapped name, or the raw label when unmapped, with #resolve_direct.
  # - #resolve_direct(raw): resolveGameCompletionPlatformId. A numeric id
  #   (only if it exists), else an exact name/abbreviation/code match, else a
  #   partial match when exactly one platform contains the value. All
  #   comparisons are trimmed and case-insensitive.
  # - #resolve_mapped(raw, among:): the Completionator rule (resolvePlatformId).
  #   Only mapped names count, matched by exact platform name against `among`
  #   (e.g. the game's platforms).
  # - #mapped_names(raw): the PLATFORM_MAP entry for a label, or [].
  #
  # `platforms:` is a GamedbPlatform relation; it is read once per resolver
  # instance (ordered by id, so exact-match ties resolve stably). Build one
  # resolver per request and reuse it across rows.
  class PlatformResolver
    PLATFORM_MAP = YAML.load_file(Rails.root.join("config/import_platform_map.yml")).freeze

    def initialize(platforms: GamedbPlatform.all)
      @platforms_source = platforms
    end

    def resolve(raw)
      key = map_key(raw)
      return if key.empty?

      mapped = PLATFORM_MAP.fetch(key, [])
      (mapped.presence || [ raw ]).each do |candidate|
        platform_id = resolve_direct(candidate)
        return platform_id if platform_id
      end
      nil
    end

    def resolve_direct(raw)
      value = comparable(raw)
      return if value.empty?

      if value.match?(/\A\d+\z/)
        id = value.to_i
        return platforms.any? { |platform| platform[:id] == id } ? id : nil
      end

      exact = platforms.find { |platform| platform[:keys].include?(value) }
      return exact[:id] if exact

      partial = platforms.select { |platform| platform[:keys].any? { |key| key.include?(value) } }
      partial.one? ? partial.first[:id] : nil
    end

    def resolve_mapped(raw, among:)
      by_name = among.to_h { |platform| [ comparable(platform.platform_name), platform.platform_id ] }
      mapped_names(raw).each do |name|
        platform_id = by_name[comparable(name)]
        return platform_id if platform_id
      end
      nil
    end

    def mapped_names(raw)
      PLATFORM_MAP.fetch(map_key(raw), [])
    end

    private

    def platforms
      @platforms ||= @platforms_source
        .order(:platform_id)
        .pluck(:platform_id, :platform_name, :platform_abbreviation, :platform_code)
        .map do |id, name, abbreviation, code|
          { id: id, keys: [ name, abbreviation, code ].filter_map { |key| comparable(key).presence } }
        end
    end

    def comparable(value)
      value.to_s.strip.downcase
    end

    def map_key(value)
      value.to_s.downcase.gsub(/\s+/, " ").strip
    end
  end
end
