# frozen_string_literal: true

# A Club Codex entry as the API serves it, the same shape for every part
# (spec #397, "Entry payload"). Fields a part doesn't use are null.
#
#   author     the member who wrote it, under the name they go by now (their
#              last known one once they have left)
#   mentions   each member `body` mentions, by Discord id
#   images     the entry's gallery (ticket #410); [] until then
#   links      its "See also" entries (ClubCodex::Links), as the acting
#              member may read them: a Visitor sees only History Events
#   viewer     what the acting member may do with it (ClubCodex::Actor)
#
# Pass `params[:actor]`, and for a page of entries `params[:mentions]`
# (ClubCodex::Mentions.of the page) and `params[:links]` (ClubCodex::Links.of
# it); a single entry reads its own. Load entries through CodexEntryResource.preloaded.
class CodexEntryResource
  include BaseResource

  attributes :id, :part, :title, :rich_body, :body

  attribute :occurred_on do |entry|
    entry.occurred_on&.iso8601
  end

  attributes :date_precision, :kind

  attribute :author do |entry|
    ClubCodex.member(entry.author)
  end

  attribute :mentions do |entry|
    mentions = params[:mentions] || ClubCodex::Mentions.of([ entry ])
    mentions.fetch(entry.id, {})
  end

  attribute :images do |_entry|
    []
  end

  attribute :links do |entry|
    links = params[:links] || ClubCodex::Links.of([ entry ], actor: params.fetch(:actor))
    links.fetch(entry.id, [])
  end

  attribute :viewer do |entry|
    params.fetch(:actor).viewer(entry)
  end

  attributes :created_at, :updated_at

  def self.preloaded(scope) = scope.preload(:author)
end
