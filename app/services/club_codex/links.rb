# frozen_string_literal: true

module ClubCodex
  # "See also" links between Club Codex entries (GLOSSARY.md, "Club Codex";
  # spec #397, ticket #409). Any entry can link to any other, and a link
  # belongs to both: it is one row (CodexEntryLink) and shows on both. An
  # entry can't link to itself, and deleting either entry removes the link.
  #
  # A link shows as the other entry's short shape, `{ id, part, title }`,
  # which the entry search (GET /api/v1/codex/entries) returns too. A Fun
  # Fact has no title, so its `title` is its opening words.
  module Links
    # The most links one entry may have.
    MAX = 50
    # A Fun Fact's opening words are at most this many characters.
    OPENING_WORDS_MAX = 60

    # A refused set of links; its message is for members.
    class Invalid < StandardError; end

    module_function

    # Replaces `entry`'s links with links to the entries `ids`. Links to
    # entries left out are removed from both sides, whoever can edit them.
    # Raises Invalid for a self-link, an unknown entry, or too many.
    def replace!(entry, ids)
      ids = entry_ids(ids)
      raise Invalid, "An entry can't link to itself." if ids.include?(entry.id)
      raise Invalid, "An entry can have at most #{MAX} links." if ids.size > MAX

      missing = ids - CodexEntry.where(id: ids).pluck(:id)
      raise Invalid, "No Club Codex entry #{missing.join(', ')}." if missing.any?

      CodexEntry.transaction do
        # One replace per entry at a time, so two don't interleave.
        entry.lock!
        CodexEntryLink.touching([ entry.id ]).where.not(low_entry_id: ids).where.not(high_entry_id: ids).delete_all
        CodexEntryLink.insert_all(ids.map { |id| CodexEntryLink.pair(entry.id, id) }) if ids.any?
      end
    rescue ActiveRecord::InvalidForeignKey
      raise Invalid, "One of those entries was just deleted."
    end

    # Each entry's links, keyed by entry id, as `actor` may read them (a
    # Visitor sees only History Events), oldest linked entry first; in two
    # queries for a page of entries.
    def of(entries, actor:)
      ids = entries.map(&:id)
      pairs = ids.empty? ? [] : CodexEntryLink.touching(ids).pluck(:low_entry_id, :high_entry_id)
      linked = pairs.empty? ? [] : actor.readable(CodexEntry.where(id: pairs.flatten.uniq)).order(:id).to_a
      shapes = summaries(linked).index_by { |link| link[:id] }

      by_entry = Hash.new { |hash, key| hash[key] = [] }
      pairs.each do |low, high|
        by_entry[low] << shapes[high] if shapes.key?(high)
        by_entry[high] << shapes[low] if shapes.key?(low)
      end
      by_entry.transform_values { |links| links.sort_by { |link| link[:id] } }
    end

    # The short shape of each entry, `{ id, part, title }`, in order.
    def summaries(entries)
      names = mentioned_names(entries.select(&:fun_fact?))
      entries.map { |entry| { id: entry.id, part: entry.part, title: title(entry, names) } }
    end

    # Its title, or a Fun Fact's opening words with mentions shown as
    # `@name` (`names`: Discord id to name).
    def title(entry, names)
      return entry.title unless entry.fun_fact?

      text = entry.body.to_s.gsub(Mentions::TOKEN) do |token|
        name = names[Regexp.last_match(1)]
        name ? "@#{name}" : token
      end.squish
      return text if text.length <= OPENING_WORDS_MAX

      # Cut at the last space that keeps it within the limit, so no word is
      # split (one long word is cut where it must be).
      cut = text[0, OPENING_WORDS_MAX + 1]
      cut = cut.include?(" ") ? cut[0, cut.rindex(" ")] : cut[0, OPENING_WORDS_MAX]
      "#{cut.sub(/[[:punct:]]+\z/, '')}…"
    end

    # The current names of the members the Fun Facts mention, by Discord id.
    def mentioned_names(fun_facts)
      ids = fun_facts.flat_map { |entry| entry.body.to_s.scan(Mentions::TOKEN).flatten }.uniq
      return {} if ids.empty?

      RpgClubUser.without_images.where(user_id: ids).to_h { |user| [ user.user_id, ClubCodex.member(user)[:name] ] }
    end

    # The given entry ids as integers, without repeats.
    def entry_ids(ids)
      valid = ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) || id.to_s.match?(/\A\d+\z/) }
      raise Invalid, "entry_ids must be a list of entry ids." unless valid

      ids.map(&:to_i).uniq
    end
  end
end
