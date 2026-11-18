# frozen_string_literal: true

module ClubCodex
  # Finding Club Codex entries by their words (spec #397, ticket #409): the
  # entry search behind the website's "See also" link picker, and the Fun
  # Fact list's `q` behind the bot's autocomplete. A query matches an
  # entry's title or its text (`body`, the Discord text, so a Lore Entry's
  # story and a Fun Fact too), any case, its characters taken literally.
  module EntrySearch
    module_function

    # The entries of `scope` that `query` matches; all of them when it is
    # blank, and none when it holds a NUL character, which no entry can
    # hold (Postgres refuses it in text).
    def matching(scope, query)
      query = query.to_s.strip
      return scope if query.empty?
      return scope.none if query.include?("\u0000")

      scope.where("codex_entries.title ILIKE :pattern OR codex_entries.body ILIKE :pattern", pattern: pattern(query))
    end

    # Title matches first, then the newest; newest first when `query` is
    # blank or matches nothing (a NUL character).
    def order(query)
      query = query.to_s.strip
      return { created_at: :desc, id: :desc } if query.empty? || query.include?("\u0000")

      Arel.sql(CodexEntry.sanitize_sql_array(
        [ "CASE WHEN codex_entries.title ILIKE ? THEN 0 ELSE 1 END, codex_entries.created_at DESC, " \
          "codex_entries.id DESC", pattern(query) ]
      ))
    end

    def pattern(query) = "%#{CodexEntry.sanitize_sql_like(query)}%"
  end
end
