# frozen_string_literal: true

module GameLists
  # Changing a Game List itself: its fields, its visibility, and deleting it.
  # Every edit and delete goes through here, so the rules for a list that
  # feeds a Challenge (the club takeover, ticket api#448) have one place to
  # live. For now a delete and a change to Private act directly.
  module Lifecycle
    module_function

    # Saves `attributes` (name, description, visibility, sort) on the list.
    # Raises ActiveRecord::RecordInvalid when the list's rules refuse them.
    def update!(list, attributes)
      list.update!(attributes)
      list
    end

    # Deletes the list with its entries.
    def destroy!(list)
      list.destroy!
      list
    end
  end
end
