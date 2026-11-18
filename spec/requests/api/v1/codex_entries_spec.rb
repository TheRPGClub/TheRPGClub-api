# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/codex/entries', type: :request do
  gate = 'Belongs to the Club Codex Feature: not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but a bot write gets 403 `feature_unavailable` when the Flag hides the ' \
         'Feature from the member it acts for.'

  path '/api/v1/codex/entries' do
    get 'Search Club Codex entries' do
      tags 'Club Codex'
      description 'The "See also" link picker\'s search, across History Events, Lore Entries and Fun Facts. ' \
                  'Needs no sign-in, but finds only what the caller may read: a Visitor (signed out) finds only ' \
                  'History Events, and only while the Feature is Live; members and the bot find every part. `q` ' \
                  'matches titles and text (`body`), any case, its characters taken literally; title matches ' \
                  'come first, then the newest. Without `q`, every readable entry, newest first. Each result is ' \
                  "the short link shape, as in an entry's `links`. #{gate}"
      produces 'application/json'
      parameter name: :q, in: :query, required: false, schema: { type: :string },
        description: 'Words to find in titles and text.'
      parameter name: :part, in: :query, required: false, schema: { type: :string, enum: CodexEntry::PARTS },
        description: 'Keep one part.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'matching entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CodexEntryLink' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'invalid_part: `part` is not one of the three parts' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/entries/{id}/links' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put "Replace an entry's \"See also\" links" do
      tags 'Club Codex'
      description 'Replaces the entry\'s links with links to `entry_ids`, entries of any part; an empty list ' \
                  'removes them all. A link belongs to both entries and shows on both, one per pair. Whoever ' \
                  'can edit this entry may (403 "Only its author or a Moderator can edit this.", or "Only ' \
                  'Admins can change Club History." for a History Event), so a Regular can link their Lore ' \
                  'Entry to a History Event, and a link to an entry the caller can\'t edit can still be ' \
                  'removed from this side. Deleting either entry removes the link. Returns the entry. Refusals ' \
                  "carry `{ error, message }`; `message` is written for members. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              acting_user_id: {
                type: :string,
                description: 'Service only, required: the Discord user id of the member the bot acts for.'
              },
              entry_ids: { type: :array, items: { type: :integer }, maxItems: ClubCodex::Links::MAX,
                           description: 'Every entry this one links to, after the change.' }
            },
            required: %w[entry_ids]
          }
        },
        required: %w[data]
      }

      response '200', 'the entry, with its links' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CodexEntry' } }
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'the caller can\'t edit the entry, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such entry, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', "invalid_links: `entry_ids` isn't a list of ids, names this entry (a self-link), an " \
                      "unknown entry, or more than #{ClubCodex::Links::MAX}" do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
