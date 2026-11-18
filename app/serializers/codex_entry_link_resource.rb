# frozen_string_literal: true

# A Club Codex entry in its short link shape (spec #397, ticket #409): what a
# "See also" link and the entry search show. `title` is the entry's title, or
# a Fun Fact's opening words (ClubCodex::Links.title).
#
# Pass `params[:names]`, the names of the members the page's Fun Facts
# mention (ClubCodex::Links.mentioned_names).
class CodexEntryLinkResource
  include BaseResource

  attributes :id, :part

  attribute :title do |entry|
    ClubCodex::Links.title(entry, params.fetch(:names))
  end
end
