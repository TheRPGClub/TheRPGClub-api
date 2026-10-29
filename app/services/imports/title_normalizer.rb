# frozen_string_literal: true

module Imports
  # Title normalisation for import matching, ported from the bot's
  # ImportTitleNormalization.ts (+ isExactImportTitleMatch from
  # ImportCandidateUtils.ts). Pure functions, no database access.
  #
  #   Imports::TitleNormalizer.normalize("The Witcher 3: Wild Hunt (2015)")
  #   # => "Witcher 3 Wild Hunt"
  #   Imports::TitleNormalizer.progressive_variants("The Witcher 3: Wild Hunt (2015)")
  #   # => ["The Witcher 3: Wild Hunt (2015)", "The Witcher 3: Wild Hunt",
  #   #     "The Witcher 3 Wild Hunt", "Witcher 3 Wild Hunt"]
  #   Imports::TitleNormalizer.exact_match?("FINAL FANTASY® VII", "Final Fantasy VII") # => true
  module TitleNormalizer
    # IMPORT_TITLE_IGNORE_STEPS, applied cumulatively in this order.
    STEPS = [
      ->(value) { value.gsub(%r{\s*\((?:19|20)\d{2}(?:[/-]\d{1,2}){0,2}\)\s*}, " ") }, # "(YYYY[-MM[-DD]])"
      ->(value) { value.gsub(/[™®]/, "") },
      ->(value) { value.gsub(/[-–—]/, " ") },
      ->(value) { value.tr(":", " ") },
      ->(value) { value.sub(/\A(the|a|an)\s+/i, "") },
      ->(value) { value.gsub(/\s+(the|a|an)\s+/i, " ") },
      ->(value) { value.gsub(/[^\p{L}\p{N}'-]+/, " ") }
    ].freeze

    module_function

    # Applies the first `step_count` STEPS (all by default) to the trimmed
    # title, then collapses whitespace.
    def normalize(title, step_count: STEPS.size)
      count = step_count.clamp(0, STEPS.size)
      value = STEPS.first(count).reduce(title.to_s.strip) { |acc, step| step.call(acc) }
      squish(value)
    end

    # The raw (trimmed) title followed by the result after each cumulative
    # step, deduped, blanks dropped. Matchers try these in order and stop at
    # the first variant with hits.
    def progressive_variants(title)
      base = title.to_s.strip
      return [] if base.empty?

      variants = [ squish(base) ]
      (1..STEPS.size).each { |count| variants << normalize(base, step_count: count) }
      variants.reject(&:empty?).uniq
    end

    # True when both titles are equal after full normalisation, ignoring case
    # (the bot's auto-match gate for a single candidate).
    def exact_match?(source_title, gamedb_title)
      normalize(source_title).downcase == normalize(gamedb_title).downcase
    end

    def squish(value)
      value.gsub(/\s+/, " ").strip
    end
    private_class_method :squish
  end
end
