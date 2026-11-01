# frozen_string_literal: true

require 'swagger_helper'

# Achievement Hub reads for www (api-09). Every route needs a signed-in
# principal; any member may read any other member's data. Departed members,
# placeholder progress rows (`synced_at` null) and removed Achievements are
# excluded everywhere (the set page lists a member's unlocked removed
# Achievements separately). Progress is per Achievement Set, never merged
# across sets.
RSpec.describe 'api/v1/achievements', type: :request do
  providers = UserLinkedAccount::PROVIDERS
  page_params = lambda do |group|
    group.parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
    group.parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
  end

  path '/api/v1/users/{user_id}/achievements/summary' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "A member's Achievement Hub summary" do
      tags 'Achievements'
      description 'Totals per Provider and overall (Unlocks, Completions, Masteries, Platinums, RA points), ' \
                  'read from the cached progress rows; the Linked Accounts (Provider and display name only); ' \
                  'the 5 latest Unlocks; and the 4 rarest Unlocks by overall Rarity (unknown Rarity last). ' \
                  '404 when the member has no Linked Account or has left the server, ' \
                  'so www shows the profile section only on a 200.'
      produces 'application/json'

      response '200', 'summary' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/MemberAchievementSummary' } },
          required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no Linked Account, departed or unknown member' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/achievements/sets' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "A member's Achievement Set progress grid" do
      tags 'Achievements'
      description 'One card per Achievement Set the member has played. `status=in_progress` keeps sets with ' \
                  'at least one Unlock and no Completion; `completed` keeps Completions; omitted lists every set. ' \
                  '`sort=recent` (default) orders by latest Unlock, `progress` by earned share, `title` A to Z.'
      produces 'application/json'
      parameter name: :provider, in: :query, schema: { type: :string, enum: providers }, required: false
      parameter name: :status, in: :query, schema: { type: :string, enum: Achievements::SetProgressGrid::STATUSES },
        required: false
      parameter name: :sort, in: :query,
        schema: { type: :string, enum: Achievements::SetProgressGrid::SORTS, default: 'recent' }, required: false
      page_params.call(self)

      response '200', 'progress grid' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/AchievementSetProgress' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unknown provider, status or sort' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/achievements/unlocks' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "A member's Unlocks" do
      tags 'Achievements'
      description "The member's Unlocks across every set, newest first."
      produces 'application/json'
      page_params.call(self)

      response '200', 'Unlocks' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/AchievementUnlock' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/achievement_sets/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'An Achievement Set page' do
      tags 'Achievements'
      description 'The set and every non-removed Achievement in `display_order`. With `user_id`, each ' \
                  "Achievement carries that member's `unlocked_at` and `hardcore`, `progress` is their progress " \
                  'row, and `removed_achievements` lists the removed Achievements they unlocked (for a "Removed" ' \
                  "footer). `viewer_unlocked` is always the signed-in viewer's own state, for spoiler blur."
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
        description: 'The member whose Unlocks and progress to show.'

      response '200', 'set page' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/AchievementSetDetail' } },
          required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown set, or `user_id` is not an active member' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/achievements/feed' do
    get 'The community Achievement feed' do
      tags 'Achievements'
      description '`view=latest` (default): cards grouping Unlocks per member + Achievement Set + UTC day of ' \
                  '`unlocked_at`, newest first, each with its count and up to 8 Unlocks (`AchievementFeedGroup`). ' \
                  '`meta.count` counts cards. `view=highlights`: one card per Highlight Unlock, newest first ' \
                  '(`AchievementFeedHighlight`). Cards carry `kind` to tell them apart.'
      produces 'application/json'
      parameter name: :view, in: :query, schema: { type: :string, enum: Achievements::Feed::VIEWS, default: 'latest' },
        required: false
      parameter name: :provider, in: :query, schema: { type: :string, enum: providers }, required: false
      page_params.call(self)

      response '200', 'feed cards' do
        schema type: :object, properties: {
          data: {
            type: :array,
            items: {
              oneOf: [
                { '$ref' => '#/components/schemas/AchievementFeedGroup' },
                { '$ref' => '#/components/schemas/AchievementFeedHighlight' }
              ],
              discriminator: { propertyName: 'kind' }
            }
          },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unknown view or provider' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/achievement_sets' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get "A GameDB game's Achievement showcase" do
      tags 'Achievements'
      description 'The Achievement Sets linked to the game (by Provider, then title), each with the members ' \
                  "who completed it (oldest Completion first) and the viewer's own progress (null when none). " \
                  'Unpaginated.'
      produces 'application/json'

      response '200', 'sets' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameAchievementSet' } }
        }, required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown game' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
