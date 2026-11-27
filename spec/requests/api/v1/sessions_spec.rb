# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/sessions', type: :request do
  path '/api/v1/session' do
    get 'Current session' do
      tags 'Sessions'
      description 'Returns the authenticated principal (Discord user or service account) and, when applicable, RPG Club membership info.'
      produces 'application/json'

      response '200', 'current session' do
        schema type: :object, properties: {
          principal: {
            type: :object,
            description: 'The authenticated principal (Auth::Principal#as_json). `kind` is ' \
                         '"discord_user" or "service"; the name/avatar fields are null for a ' \
                         'service principal.',
            properties: {
              kind: { type: :string, example: 'discord_user' },
              id: { type: :string },
              discord_id: { type: :string, nullable: true },
              username: { type: :string, nullable: true },
              global_name: { type: :string, nullable: true },
              avatar: { type: :string, nullable: true },
              service: { type: :boolean },
              dev: { type: :boolean },
              longstanding: { type: :boolean }
            },
            required: %w[kind id service dev longstanding]
          },
          membership: {
            type: :object,
            nullable: true,
            description: 'RPG Club membership flags (RpgClubUser#membership) merged with the ' \
                         'caller\'s dev/longstanding flags. `admin`, `moderator`, `regular` and ' \
                         '`member` follow the member\'s Discord roles: refreshed at sign-in and ' \
                         'whenever the bot reports a role change. Null for a service principal or an ' \
                         'unknown user.',
            properties: {
              admin: { type: :boolean },
              moderator: { type: :boolean },
              regular: { type: :boolean },
              member: { type: :boolean },
              newcomer: { type: :boolean },
              active: { type: :boolean },
              dev: { type: :boolean },
              longstanding: { type: :boolean }
            }
          },
          features: {
            type: :array,
            description: 'The Features this viewer may see, in registry order (Features::Access). ' \
                         'Admins and Superadmins get every Feature in every state; anyone else gets ' \
                         'only Live Features, so a Preview or Off Feature never reaches a member. A ' \
                         'Feature with no stored Feature Flag state reads as Preview.',
            items: {
              type: :object,
              properties: {
                key: { type: :string, example: 'reviews' },
                name: { type: :string, example: 'Reviews' },
                state: { type: :string, enum: %w[off preview live] },
                hideable: { type: :boolean, description: 'False for a Core Feature, which members cannot hide.' },
                shown: {
                  type: :boolean,
                  description: 'Whether the website shows this Feature to the viewer: they can use it, have not ' \
                               'hidden it with a Feature Preference, and, for staff with "show Preview features" ' \
                               'off, it is not in Preview. A hidden Feature stays listed with `shown: false`.'
                },
                preview: {
                  type: :boolean,
                  description: 'True when the viewer sees the Feature only because they are staff (Preview).'
                }
              },
              required: %w[key name state hideable shown preview]
            }
          },
          pinned_pages: {
            type: :array,
            items: { type: :string, example: 'voting' },
            description: 'The viewer\'s Pinned Pages they can see right now, in their order (as GET ' \
                         '/api/v1/users/{user_id}/pinned_pages). Empty for the service token.'
          },
          pinned_pages_customised: {
            type: :boolean,
            description: 'Whether the viewer saved their own Pinned Pages (`customised` in GET ' \
                         '/api/v1/users/{user_id}/pinned_pages). False while they follow the club default, and ' \
                         'for the service token.'
          },
          pinned_pages_room: {
            type: :integer, minimum: 0, example: 5,
            description: 'How many Pinned Pages the viewer can see room for: `pinned_pages_limit` less the pins ' \
                         'they can\'t see right now (a Feature Off or hidden, a staff role lost), which a save ' \
                         'keeps and the limit counts. The website treats the list as full once `pinned_pages` ' \
                         'reaches it. The whole limit for the service token.'
          },
          pinned_pages_default: {
            type: :array,
            items: { type: :string, example: 'voting' },
            description: 'The club default Pinned Pages, in order, that a member follows until they save their ' \
                         'own list (and again after a reset). Every key, seen by the viewer or not.'
          },
          pinned_pages_limit: {
            type: :integer, example: 6,
            description: 'The most Pinned Pages a member may keep, counting the ones they can\'t see right now.'
          },
          patch_notes_unseen: {
            type: :boolean,
            description: 'Whether a published Patch is newer than the member\'s Patch Mark (any published Patch ' \
                         'while they have none), for the sidebar\'s "NEW" mark. False when Patch Notes is not ' \
                         'shown to the viewer (Off, Preview for a non-staff member, hidden by a Feature ' \
                         'Preference) and for the service token.'
          },
          patch_mark: {
            type: :integer, nullable: true, example: 12,
            description: 'The member\'s Patch Mark: the number of the newest Patch they have seen (as GET ' \
                         '/api/v1/users/{user_id}/patch_mark). Null until first set, and whenever ' \
                         '`patch_notes_unseen` is forced false because Patch Notes is not shown.'
          },
          theme: {
            type: :string, example: 'monthly-issue',
            description: 'The key of the Theme the viewer sees right now, already resolved: the club default ' \
                         '(monthly-issue) whenever their stored Theme is unset, unavailable to them or unknown ' \
                         '(docs/adr/0017). As `theme` in PUT /api/v1/me/theme.'
          },
          themes: {
            type: :object,
            description: 'The picker\'s Themes and the viewer\'s stored choice (`themes` in the MemberTheme ' \
                         'schema, as PUT /api/v1/me/theme returns it).',
            properties: {
              chosen: { type: :string, nullable: true, example: 'aero' },
              list: { type: :array, items: { '$ref' => '#/components/schemas/ThemeOption' } }
            },
            required: %w[chosen list]
          }
        }, required: %w[principal features pinned_pages pinned_pages_customised pinned_pages_room
                        pinned_pages_default pinned_pages_limit patch_notes_unseen patch_mark theme themes]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
