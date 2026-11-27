# frozen_string_literal: true

# The website's Themes (GLOSSARY.md "Theme", "Released Theme"; spec api#523;
# docs/adr/0017): the looks a Member may choose.
#
# The API owns this list, in code, as it owns Pinned Pages (docs/adr/0012);
# the website's themes/registry.ts maps each key to its stylesheet and is
# tested against these keys. Adding a Theme means an API release, unreleased
# first; releasing one is a one-line change to `released`.
#
# A Member's stored Theme is RpgClubUser#theme, NULL to follow DEFAULT. Who
# may choose which Theme is decided by Themes::Choice.
module Themes
  # The club's default Theme: visitors, Members who never chose, and anyone
  # whose stored Theme is unavailable to them see it. Always available.
  DEFAULT = "monthly-issue"

  Theme = Data.define(:key, :name, :released) do
    def released? = released
  end

  def self.theme(key, name, released:) = Theme.new(key: key, name: name, released: released)
  private_class_method :theme

  LIST = [
    theme("monthly-issue", "Monthly Issue", released: true),
    theme("aero", "Frutiger Aero", released: false)
  ].freeze

  BY_KEY = LIST.index_by(&:key).freeze

  def self.all = LIST

  def self.keys = BY_KEY.keys

  def self.known?(key) = key.is_a?(String) && BY_KEY.key?(key)

  def self.fetch(key) = BY_KEY.fetch(key)
end
