# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/game_lists', type: :request do
  gate = 'Members (the `game_lists` Feature): not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but a bot write gets 403 `feature_unavailable` when the Flag hides the ' \
         'Feature from the member it acts for.'
  acting_read = 'The bot may name the member it reads for with `acting_user_id`, without which it sees what a ' \
                'member with no lists of their own sees.'
  acting_user_id = {
    type: :string,
    description: 'Service only, required on every write: the Discord user id of the member the bot acts for. ' \
                 'Their stored roles decide what they may do, and the Feature Flag applies to them.'
  }
  refusal = 'Refusals carry `{ error, message }`; `message` is written for members (403 `forbidden`, 422 ' \
            '`invalid_game_list`).'
  rules = 'A Private list is read and changed only by its owner (staff can\'t read it either; it is not found for ' \
          'them). The owner does everything with their own lists; Moderators and above edit club lists and any ' \
          'Members-visible list, and delete a member\'s Members-visible list; only Admins and above delete a club ' \
          'list; only the owner changes visibility.'
  list_fields = {
    name: { type: :string, maxLength: GameList::NAME_MAX },
    description: { type: :string, nullable: true, maxLength: GameList::DESCRIPTION_MAX },
    visibility: { type: :string, enum: GameList::VISIBILITIES, description: 'members when left out on create. ' \
                                                                           'Only the owner changes it.' },
    sort: { type: :string, enum: GameList::SORTS, description: 'ranked when left out on create.' }
  }
  list_page = {
    type: :object, properties: {
      data: { type: :array, items: { '$ref' => '#/components/schemas/GameList' } },
      meta: { '$ref' => '#/components/schemas/PaginationMeta' }
    }
  }
  feeds = { '$ref' => '#/components/schemas/GameListFeedsChallenges' }
  one_list = { type: :object, properties: { data: { '$ref' => '#/components/schemas/GameList' } } }
  one_entry = { type: :object, properties: { data: { '$ref' => '#/components/schemas/GameListEntry' } } }
  error = { '$ref' => '#/components/schemas/Error' }
  page_params = lambda do |group|
    group.parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
    group.parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
    group.parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
  end

  path '/api/v1/game_lists' do
    get 'List Game Lists' do
      tags 'Game Lists'
      description 'The lists the caller may read (every Members-visible list, and their own Private ones): club ' \
                  "lists first, then the most recently changed (a change to its games counts). #{acting_read} " \
                  "#{gate}"
      produces 'application/json'
      parameter name: :q, in: :query, required: false, schema: { type: :string },
        description: 'Only lists whose name contains `q`, ignoring case, its characters taken literally.'
      parameter name: :game_id, in: :query, required: false, schema: { type: :integer },
        description: 'Only lists holding this game.'
      parameter name: :owner, in: :query, required: false, schema: { type: :string },
        description: '`club` for the club\'s lists, or a member\'s Discord user id for theirs.'
      page_params.call(self)

      response '200', 'Game Lists, without their entries' do
        schema list_page
      end

      response '401', 'not signed in' do
        schema error
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema error
      end
    end

    post 'Create a Game List' do
      tags 'Game Lists'
      description 'Any member creates a list they own; with `club`, a Moderator or above creates a club list ' \
                  '(403 "Only Moderators and above can create a club Game List."), which is always Members-' \
                  "visible. Returns the list. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: list_fields.merge(acting_user_id: acting_user_id,
              club: { type: :boolean, description: 'The club owns it (Moderator and above).' }),
            required: %w[name]
          }
        },
        required: %w[data]
      }

      response '201', 'the new list' do
        schema one_list
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id` (or one with no stored record)' do
        schema error
      end

      response '403', '`forbidden` for a club list without the role, or (bot) `feature_unavailable`' do
        schema error
      end

      response '422', 'invalid_game_list: a missing or too long name, a too long description, an unknown ' \
                      'visibility or sort, a field that isn\'t text, or a Private club list' do
        schema error
      end
    end
  end

  path '/api/v1/game_lists/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a Game List' do
      tags 'Game Lists'
      description "The list with every game, in its sort's order. #{rules} #{acting_read} #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the list with its entries' do
        schema one_list
      end

      response '404', 'no such list, a Private list of someone else, or the Feature is hidden from the caller' do
        schema error
      end
    end

    patch 'Edit a Game List' do
      tags 'Game Lists'
      description "Changes only the fields given. #{rules} 403 \"#{GameLists::Refusals::EDIT}\", or " \
                  "\"#{GameLists::Refusals::VISIBILITY}\" for a visibility change by someone else. Making a " \
                  'list that feeds a Pool Challenge Private is 409 `list_feeds_challenges` (naming the ' \
                  'Challenges) unless `confirm`; with it, the club keeps a Members-visible copy (taken over from ' \
                  'the owner) that the Challenges relink to, and the owner\'s list goes Private. Returns the ' \
                  "list. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: list_fields.merge(acting_user_id: acting_user_id,
          confirm: { type: :boolean, description: 'Go ahead though the list feeds a Challenge.' }) } },
        required: %w[data]
      }

      response '200', 'the list' do
        schema one_list
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema error
      end

      response '403', 'the caller can\'t edit it, or change its visibility; or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'no such list the caller can read, or the Feature is hidden from the caller' do
        schema error
      end

      response '409', 'list_feeds_challenges: confirm needed' do
        schema feeds
      end

      response '422', 'invalid_game_list, as on create' do
        schema error
      end
    end

    delete 'Delete a Game List' do
      tags 'Game Lists'
      description "Deletes the list with its entries. #{rules} 403 \"#{GameLists::Refusals::DELETE}\". A list " \
                  'that feeds a Pool Challenge needs `confirm` (409 `list_feeds_challenges`, naming the ' \
                  'Challenges): a member\'s list then goes to the club instead (`owner` null, `taken_over_from` ' \
                  'set, Members-visible; `taken_over: true`) and keeps feeding them; a club list is deleted and ' \
                  'the links end, the Challenges keeping their games. The bot names the member with the ' \
                  "`acting_user_id` query parameter. #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :confirm, in: :query, required: false, schema: { type: :boolean },
        description: 'Go ahead though the list feeds a Challenge.'

      response '200', 'deleted, or taken over by the club' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean },
                                               taken_over: { type: :boolean,
                                                             description: 'The club kept it, as it feeds a Challenge.' } } }
        }
      end

      response '409', 'list_feeds_challenges: confirm needed' do
        schema feeds
      end

      response '400', 'the bot named no `acting_user_id`' do
        schema error
      end

      response '403', 'the caller can\'t delete it, or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'no such list the caller can read, or the Feature is hidden from the caller' do
        schema error
      end
    end
  end

  path '/api/v1/game_lists/{id}/entries/order' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put "Set a Game List's ranked order" do
      tags 'Game Lists'
      description '`game_ids` names every game of the list once, first to last; each game\'s `position` follows. ' \
                  'The ranked order is kept whatever the list\'s sort. Whoever can edit the list may. Returns ' \
                  "the list. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { acting_user_id: acting_user_id,
                          game_ids: { type: :array, items: { type: :integer }, maxItems: GameList::ENTRIES_MAX } },
            required: %w[game_ids]
          }
        },
        required: %w[data]
      }

      response '200', 'the list in its new order' do
        schema one_list
      end

      response '403', 'the caller can\'t edit the list, or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'no such list the caller can read, or the Feature is hidden from the caller' do
        schema error
      end

      response '422', 'invalid_order: `game_ids` leaves a game out, repeats one or names one not in the list' do
        schema error
      end
    end
  end

  path '/api/v1/game_lists/{id}/entries/{game_id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true

    post 'Add a game to a Game List' do
      tags 'Game Lists'
      description 'Adds the GameDB game last in the ranked order, with an optional note. A list holds a game at ' \
                  "most once and at most #{GameList::ENTRIES_MAX} games. Whoever can edit the list may. #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { acting_user_id: acting_user_id,
                          note: { type: :string, nullable: true, maxLength: GameListEntry::NOTE_MAX } }
          }
        }
      }

      response '201', 'the entry' do
        schema one_entry
      end

      response '403', 'the caller can\'t edit the list, or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'no such list the caller can read or no such game, or the Feature is hidden from the caller' do
        schema error
      end

      response '409', 'already_in_list: the list holds the game' do
        schema error
      end

      response '422', "list_full: the list holds #{GameList::ENTRIES_MAX} games; invalid_game_list: a note over " \
                      "#{GameListEntry::NOTE_MAX} characters or not text" do
        schema error
      end
    end

    patch "Change a game's note" do
      tags 'Game Lists'
      description 'Replaces the note; null or blank removes it. Whoever can edit the list may. ' + gate
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { acting_user_id: acting_user_id,
                          note: { type: :string, nullable: true, maxLength: GameListEntry::NOTE_MAX } },
            required: %w[note]
          }
        },
        required: %w[data]
      }

      response '200', 'the entry' do
        schema one_entry
      end

      response '403', 'the caller can\'t edit the list, or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'the list doesn\'t hold the game, or no such list the caller can read' do
        schema error
      end

      response '422', 'invalid_game_list: no `note`, or one too long or not text' do
        schema error
      end
    end

    delete 'Remove a game from a Game List' do
      tags 'Game Lists'
      description 'Removes the game; the games after it move up one place. Whoever can edit the list may. The ' \
                  "bot names the member with the `acting_user_id` query parameter. #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'removed' do
        schema type: :object, properties: {
          data: { type: :object, properties: { game_list_id: { type: :integer }, game_id: { type: :integer },
                                               deleted: { type: :boolean } } }
        }
      end

      response '403', 'the caller can\'t edit the list, or (bot) `feature_unavailable`' do
        schema error
      end

      response '404', 'the list doesn\'t hold the game, or no such list the caller can read' do
        schema error
      end
    end
  end

  path '/api/v1/users/{user_id}/game_lists' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "List a member's Game Lists" do
      tags 'Game Lists'
      description 'For their profile: all of the caller\'s own lists, or another member\'s Members-visible ones, ' \
                  "most recently changed first. #{acting_read} #{gate}"
      produces 'application/json'
      page_params.call(self)

      response '200', 'the member\'s lists, without their entries' do
        schema list_page
      end

      response '404', 'the Feature is hidden from the caller' do
        schema error
      end
    end
  end

  path '/api/v1/games/{id}/game_lists' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get "List a game's Game Lists" do
      tags 'Game Lists'
      description 'The lists holding the game that the caller may read, club lists first, then the most recently ' \
                  "changed; `meta.count` is how many there are (\"In 4 Game Lists\"). #{acting_read} #{gate}"
      produces 'application/json'
      page_params.call(self)

      response '200', 'the lists, without their entries' do
        schema list_page
      end

      response '404', 'no such game, or the Feature is hidden from the caller' do
        schema error
      end
    end
  end
end
