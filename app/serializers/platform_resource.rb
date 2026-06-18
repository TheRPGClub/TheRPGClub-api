# frozen_string_literal: true

# Serializes a GamedbPlatform.
#
# Consumer-audited allowlist (#36, revised #106): the web frontend reads
# `platform_id` and `platform_name`; `platform_code` is kept because the Discord
# bot keys on platform codes. The Game read-path migration (#106) added two more
# columns the bot now reads off the wire:
#   - `platform_abbreviation` — completion autocomplete and display labels
#   - `igdb_platform_id`       — maps IGDB platform ids to internal records on
#                                CSV / release-date import
# The remaining IGDB sync bookkeeping (`platform_slug`, `platform_checksum`,
# `igdb_updated_at`) is still internal, read by no consumer, and dropped here —
# it stays available on the full record via platforms#show.
class PlatformResource
  include BaseResource

  attributes :platform_id, :platform_code, :platform_name,
             :platform_abbreviation, :igdb_platform_id
end
