# frozen_string_literal: true

module Api
  module V1
    # A member's News Category Preferences (spec #355, ticket #357): the News
    # Categories they switched off, which the News Hub feed leaves out of its
    # default result (NewsItemsController#index). A small document in the
    # shape of FeaturePreferencesController.
    #
    # Only the member themself may read or change it. Preferences only shape
    # the website, so the bot's service token is refused too.
    class NewsCategoryPreferencesController < ApplicationController
      feature :news_hub

      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/news_category_preferences
      def show
        render json: { data: document(params[:user_id]) }
      end

      # PATCH /api/v1/users/:user_id/news_category_preferences
      # Body: { "data": { "hidden": { "<category key>": true|false, ... } } }
      # Switches each named News Category off (true) or on again (false) and
      # leaves the others untouched. Any invalid part refuses the whole change
      # with 422. Switching off one already off is a no-op, also when two
      # requests do it at once.
      def update
        hidden = request_data["hidden"]
        error = hidden_error(hidden)
        return render(json: { error: error }, status: :unprocessable_content) if error

        user = RpgClubUser.find_or_create_by!(user_id: params[:user_id])
        off, on = hidden.keys.partition { |key| hidden[key] }
        MemberNewsCategoryPreference.transaction do
          if off.any?
            MemberNewsCategoryPreference.insert_all(off.map { |key| { user_id: user.user_id, category_key: key } },
              unique_by: %i[user_id category_key])
          end
          MemberNewsCategoryPreference.where(user_id: user.user_id, category_key: on).delete_all if on.any?
        end

        render json: { data: document(user.user_id) }
      end

      private

      # require_owner! lets the service token act as any member; preferences
      # are the member's own, so it is refused here first.
      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def hidden_error(hidden)
        return "hidden required" if hidden.nil?
        return "hidden must be an object of News Category keys to true or false" unless hidden.is_a?(Hash)

        hidden.each do |key, hide|
          return "unknown News Category: #{key}" unless NewsCategory.known?(key)
          return "hidden.#{key} must be true or false" unless [ true, false ].include?(hide)
        end
        nil
      end

      def document(user_id)
        hidden = MemberNewsCategoryPreference.hidden_keys(user_id)
        {
          user_id: user_id,
          hidden: hidden,
          categories: NewsCategory.all.map { |category| category.to_h.merge(hidden: hidden.include?(category.key)) }
        }
      end
    end
  end
end
