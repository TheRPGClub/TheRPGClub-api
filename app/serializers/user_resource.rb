# frozen_string_literal: true

# The full user-profile payload served by users#show. Replaces the hand-built
# `user.as_json.merge(...)`: the consumer-audited UserFields columns plus
# `membership`, the embedded `socials`, the four embedded preview lists and the
# `counts` summary.
#
# The previews and counts are not associations on the user — the controller
# pre-fetches limited, preloaded, ordered slices (and the count tallies) and
# hands them in via Alba `params`, so the resource serializes those exact
# scopes rather than re-querying. Each preview reuses the #32 entry resource so
# the embedded entries carry their joined `game`/`platform` (the reviews
# preview embeds `one :game`), unblocking the frontend to drop its per-list
# fan-out (TheRPGClub-www#11). Previews and counts of a Feature the viewer
# cannot use are not handed in, so they are absent from the payload.
class UserResource
  include BaseResource
  include UserFields

  attributes :membership
  many :socials, resource: UserSocialResource

  # A preview the controller left out (its Feature is one the viewer cannot
  # use, spec #347) is left out of the payload too.
  many :now_playing, resource: NowPlayingEntryResource, source: ->(params) { params[:now_playing] }, if: proc { params.key?(:now_playing) }
  many :favorites,   resource: FavoriteEntryResource,   source: ->(params) { params[:favorites] || [] }
  many :reviews,     resource: ReviewEntryResource,     source: ->(params) { params[:reviews] }, if: proc { params.key?(:reviews) }
  many :completions, resource: CompletionEntryResource, source: ->(params) { params[:completions] }, if: proc { params.key?(:completions) }
  many :journal,     resource: JournaledGameResource,   source: ->(params) { params[:journal] }, if: proc { params.key?(:journal) }

  attribute :counts do
    params[:counts] || {}
  end
end
