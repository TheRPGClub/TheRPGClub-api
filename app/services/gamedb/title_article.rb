# frozen_string_literal: true

module Gamedb
  # GameDB stores a title's leading English article at its end, so titles sort
  # by their first significant word (docs/adr/0004). Pure functions, no
  # database access.
  #
  #   Gamedb::TitleArticle.to_end("The Witcher 3: Wild Hunt") # => "Witcher 3: Wild Hunt, The"
  #   Gamedb::TitleArticle.to_front("Sims, The")              # => "The Sims"
  #   Gamedb::TitleArticle.strip("The Last of Us")            # => "Last of Us"
  #   Gamedb::TitleArticle.strip("Last of Us, The")           # => "Last of Us"
  module TitleArticle
    LEADING = /\A(the|a|an)\s+(.*\S)\z/i
    TRAILING = /\A(.*\S),\s*(the|a|an)\z/i

    module_function

    # "The Sims" -> "Sims, The". A title that is only an article, or already
    # has it at the end, is returned trimmed but otherwise unchanged.
    def to_end(title)
      value = title.to_s.strip
      match = LEADING.match(value)
      match ? "#{match[2]}, #{match[1]}" : value
    end

    # "Sims, The" -> "The Sims", for anything outside GameDB that expects the
    # title as people write it (e.g. the HLTB search).
    def to_front(title)
      value = title.to_s.strip
      match = TRAILING.match(value)
      match ? "#{match[2]} #{match[1]}" : value
    end

    # The title without its article, leading or trailing.
    def strip(title)
      value = title.to_s.strip
      if (match = LEADING.match(value)) then match[2]
      elsif (match = TRAILING.match(value)) then match[1]
      else value
      end
    end
  end
end
