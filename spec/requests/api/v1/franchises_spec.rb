# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/franchises', type: :request do
  path '/api/v1/franchises' do
    get 'List franchises' do
      tags 'Franchises'
      description 'Returns the IGDB-curated game franchises. Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'franchises list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Franchise' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a franchise, or upsert one by IGDB id' do
      tags 'Franchises'
      description 'Two uses. Without `igdb_franchise_id`, a Regular or above (by the acting member\'s stored ' \
                  'roles; the bot names it in `data.acting_user_id`) creates a Franchise IGDB doesn\'t have, ' \
                  'returning 201. With `igdb_franchise_id`, the admin/service find-or-create keyed on it (the ' \
                  'bot\'s `ensureFranchise`): the existing franchise with 200 when the IGDB id is already known, ' \
                  'or a new one with 201; `name` is applied only when a new row is created. It resolves as an ' \
                  'IGDB import does: a merged Franchise answers with its merge target (200), and one an Admin ' \
                  'deleted is refused with 422 `franchise_deleted`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              name: { type: :string, maxLength: 255, description: 'Franchise name (set only on create).' },
              igdb_franchise_id: { type: :integer, description: 'IGDB franchise id: the upsert key. Leave it out ' \
                                                                 'to create a Franchise by hand.' },
              acting_user_id: { type: :string, description: 'Bot only, creating by hand: the member it acts for.' }
            },
            required: %w[name]
          }
        },
        required: %w[data]
      }

      response '201', 'franchise created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '200', 'existing franchise (matched on IGDB id), or the one it was merged into' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '400', 'missing `data`, or the bot creating by hand names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: an upsert by a caller who is not an admin or the service, or a hand-made ' \
                      'Franchise by a member below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (an empty `igdb_franchise_id`, or a blank or too-long `name`), or ' \
                      'the IGDB id names a Franchise an Admin deleted (`franchise_deleted`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    get 'Show franchise' do
      tags 'Franchises'
      description 'A Franchise\'s page: its columns, its games grouped as `mainline`, `other` and `add_ons` ' \
                  '(games with a parent game, under their parent when it is in GameDB), each with cover and ' \
                  'release year, oldest first, and `viewer` (what the acting member may change).'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member `viewer` is for.'

      response '200', 'franchise' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchisePage' } }
      end

      response '404', 'franchise not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    patch 'Rename a franchise' do
      tags 'Franchises'
      description 'Admins and above (the acting member\'s stored roles). Renames the Franchise and sets ' \
                  '`name_locked`, so IGDB re-imports keep the name. Recorded in the history (undoable).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            required: %w[name],
            properties: {
              name: { type: :string, maxLength: 255 },
              acting_user_id: { type: :string, description: 'Bot only: the member it acts for.' }
            }
          }
        }
      }

      response '200', 'the renamed franchise' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '400', 'missing `data`, or the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'a blank or too-long `name`, or the Franchise was merged (`franchise_merged`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a franchise' do
      tags 'Franchises'
      description 'Admins and above. Deletes the Franchise and its links, takes it out of every Pool\'s ' \
                  'sources (Core Games stay), and remembers an IGDB Franchise so re-imports don\'t create it ' \
                  'again. Franchises merged into it go too, and so do its Conquests. Recorded in the history ' \
                  '(not undoable).'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member it acts for.'

      response '204', 'deleted' do
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/merge' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
      description: 'The GamedbFranchise to merge away.'

    post 'Merge a franchise into another' do
      tags 'Franchises'
      description 'Admins and above. Moves the links to `into_id` (a game in both stays Mainline if it was in ' \
                  'either), moves remembered unlinks, repoints Pool sources and sets `merged_into_id`, so ' \
                  're-imports naming the merged IGDB id resolve to the target. Recorded in the target\'s ' \
                  'history (not undoable). Its Conquests move to the target; a member with one in both keeps ' \
                  'the earlier. Answers with the target.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            required: %w[into_id],
            properties: {
              into_id: { type: :integer, description: 'The Franchise to merge into.' },
              acting_user_id: { type: :string, description: 'Bot only: the member it acts for.' }
            }
          }
        }
      }

      response '200', 'the target franchise' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '400', 'missing `data`, or the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise or target not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'into itself (`invalid_merge`), or either side already merged (`franchise_merged`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/changes' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    get 'A franchise\'s change history' do
      tags 'Franchises'
      description 'Regulars and above. Every change to the Franchise, newest first, with who made it, who ' \
                  'undid it and whether the viewer can undo it now.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 25, maximum: 500 }, required: false
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member it acts for.'

      response '200', 'changes' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/FranchiseChange' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise not found (or deleted)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchise_changes/{id}/undo' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'The change id.'

    post 'Undo a franchise change' do
      tags 'Franchises'
      description 'Regulars and above. Undoes a link, unlink, Mainline or rename change and marks it undone ' \
                  '(`undone_at`, `undone_by`); no new history row is written. Refused when the change was ' \
                  'already undone, or a later change (or a merge, or a change outside the history) touched ' \
                  'the same game or name.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { acting_user_id: { type: :string, description: 'Bot only: the member it acts for.' } }
          }
        }
      }

      response '200', 'the change, now undone' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchiseChange' } }
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'change not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', '`already_undone`, or `superseded` by a later change' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'create, merge and delete can\'t be undone (`not_undoable`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/games/{game_id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'
    parameter name: :game_id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    put 'Link a game to a franchise' do
      tags 'Franchises'
      description 'Regulars and above (the acting member\'s stored roles). Links the game as `manual` if it ' \
                  'isn\'t linked (forgetting an earlier unlink of the pair), and sets Mainline when `mainline` ' \
                  'is given. An existing link keeps its source. Hand links survive IGDB re-imports. Members ' \
                  'who now hold every Mainline game Conquer the Franchise (announced).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              mainline: { type: :boolean, description: 'Mark (true) or unmark (false) the game as Mainline; ' \
                                                        'leave out to keep it.' },
              acting_user_id: { type: :string, description: 'Bot only: the member it acts for.' }
            }
          }
        }
      }

      response '200', 'the link' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchiseLink' } }
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise or game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`mainline` is not a boolean (`invalid_mainline`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Unlink a game from a franchise' do
      tags 'Franchises'
      description 'Regulars and above. Removes the link and remembers it, so an IGDB re-import doesn\'t add it ' \
                  'back. Succeeds also when the game wasn\'t linked. Members who now hold every Mainline game ' \
                  'Conquer the Franchise (announced).'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member it acts for.'

      response '204', 'unlinked' do
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise or game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/progress' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    get "A member's Franchise Progress" do
      tags 'Franchise Progress'
      description 'Behind the `franchise_progress` Feature. The member\'s three meters (Mainline, `all` = ' \
                  'Mainline and spin-offs, spin-offs), when they Conquered the Franchise, and its Mainline and ' \
                  'spin-off games with `done`, `completion_type` and `playtime_minutes`. A game is done with any ' \
                  'Game Completion of it; Add-ons are left out and an Alternate Version\'s Completion doesn\'t ' \
                  'count. Any signed-in member reads anyone\'s.'
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
        description: 'The member; defaults to the signed-in member. The bot must give it.'

      response '200', 'progress' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchiseProgress' } }
      end

      response '400', 'the bot gave no `user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown franchise or member, or the Feature is not open to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/progress/members' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    get 'The Franchise Progress members table' do
      tags 'Franchise Progress'
      description 'Behind the `franchise_progress` Feature. Every current member with Playtime, a Game ' \
                  'Completion (Add-ons aside) or a Conquest in the Franchise, with their meters. Conquered ' \
                  'members first, earliest Conquest first; then by Mainline games done (by all games when the ' \
                  'Franchise has no Mainline games), then by Playtime. Each `user` carries their avatar ' \
                  '(`discord_avatar` hash and the stored `avatar_url` path). Not paginated.'
      produces 'application/json'

      response '200', 'members' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/FranchiseProgressMember' } }
        }
      end

      response '404', 'unknown franchise, or the Feature is not open to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
