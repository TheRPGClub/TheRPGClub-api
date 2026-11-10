# frozen_string_literal: true

# A News Category (GLOSSARY.md, "News Hub"; spec #355; docs/adr/0006): one of
# the fixed kinds of news the club sorts News Items into. The list is defined
# here, in code, in the order members see it. Each has a stable key, which
# News Items, the bot's thread configuration and the News Import file store,
# and a display name. Adding or renaming one is a release (and a Discord
# thread for the bot to watch); a key must never change once News Items use it.
NewsCategory = Data.define(:key, :name, :position)

class NewsCategory
  ALL = [
    [ "announcements", "Announcements & Trailers" ],
    [ "releases", "Releases & Updates" ],
    [ "emulation", "Emulation & Preservation" ],
    [ "industry", "Industry" ],
    [ "hardware", "Hardware & Platforms" ],
    [ "rumours", "Rumours & Leaks" ],
    [ "general", "General" ]
  ].each_with_index.map { |(key, name), index| new(key: key, name: name, position: index + 1) }.freeze

  KEYS = ALL.map(&:key).freeze

  def self.all = ALL

  def self.keys = KEYS

  def self.known?(key) = KEYS.include?(key.to_s)
end
