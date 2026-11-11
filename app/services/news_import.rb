# frozen_string_literal: true

# The News Import (GLOSSARY.md, "News Hub"; spec #355, ticket #359): the
# one-time move of the Game News Archive's messages into the News Hub as
# imported News Items, hidden until staff assign their News Categories.
module NewsImport
  # Counts of imported News Items: sorted (with a News Category), unsorted,
  # and removed by staff with `skip`; and the oldest message imported so far
  # (oldest_message_id). For the history copy (ticket #368), counts of all
  # News Items, live and imported: `copied`, with a News Copy, and
  # `uncopied`, with a News Category but no News Copy yet (NewsItem.uncopied,
  # what is left to copy; unsorted items wait for a News Category first).
  def self.status
    counts = NewsItem.imported.group(Arel.sql("category_key IS NOT NULL")).count
    { sorted: counts.fetch(true, 0), unsorted: counts.fetch(false, 0), removed: NewsImportRemoval.count,
      oldest_message_id: oldest_message_id, copied: NewsItem.copied.count, uncopied: NewsItem.uncopied.count }
  end

  # The oldest archive message the scan has recorded (by snowflake, so by
  # posting time), whether staff kept or removed it; nil before any. The
  # archive is locked, and the scan reads it newest first, so a re-run scan
  # continues from just before this message.
  def self.oldest_message_id
    oldest = [ NewsItem.imported, NewsImportRemoval ].filter_map do |scope|
      scope.minimum(Arel.sql("message_id::numeric"))
    end.min
    oldest&.to_i&.to_s
  end
end
