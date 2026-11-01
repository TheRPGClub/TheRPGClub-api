# frozen_string_literal: true

module Api
  module V1
    # A member's Linked Accounts (api-05): list, link, unlink, Retry and Sync
    # now. Owner-only (the bot service counts as the owner); an admin may also
    # unlink any member's Linked Account. Every write that makes an account
    # due kicks its Provider's tick, which drains the durable sync state
    # (ADR 0003).
    class LinkedAccountsController < ApplicationController
      before_action :require_owner!, only: %i[index]

      # GET /api/v1/users/:user_id/linked_accounts
      # At most one per Provider, so the list is not paginated.
      def index
        accounts = UserLinkedAccount.where(user_id: params[:user_id]).order(:provider)
        render json: { data: serialize(accounts) }
      end

      private

      def serialize(account_or_accounts)
        LinkedAccountResource.new(account_or_accounts, params: { now: Time.current }).serializable_hash
      end
    end
  end
end
