# frozen_string_literal: true

# Patch Notes (GLOSSARY.md "Patch Notes"; spec api#510).
module PatchNotes
  # The sections a Patch sorts its changes into, by their H2 heading.
  SECTIONS = %w[new improved fixed].freeze

  HEADINGS = %w[h1 h2].freeze
  LISTS = %w[ul ol].freeze

  # How many changes a Patch's Plate value lists under each of its New,
  # Improved and Fixed sections: the top-level items of the lists that follow
  # an H2 named "New", "Improved" or "Fixed" (any case), up to the next H1 or
  # H2. Nested items are details of one change and don't count, nor does
  # anything outside those sections.
  def self.counts(rich_body)
    counts = SECTIONS.index_with(0)
    section = nil
    Array(rich_body).each do |node|
      next unless node.is_a?(Hash)

      type = node["type"]
      if HEADINGS.include?(type)
        name = text(node).strip.downcase
        section = type == "h2" && SECTIONS.include?(name) ? name : nil
      elsif section && LISTS.include?(type)
        counts[section] += Array(node["children"]).count { |item| item.is_a?(Hash) && item["type"] == "li" }
      end
    end
    counts
  end

  def self.text(node)
    return node["text"].to_s if node.key?("text")

    Array(node["children"]).select { |child| child.is_a?(Hash) }.map { |child| text(child) }.join
  end
  private_class_method :text
end
