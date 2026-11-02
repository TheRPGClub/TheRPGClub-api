# frozen_string_literal: true

module Api
  module V1
    # The guild's Discord channels (web parity 2, #313). The bot is the only
    # writer: it replaces the whole list at startup (#sync) and upserts or
    # removes single channels on create, update and delete. Any authenticated
    # caller can list the text channels, which back the website's channel
    # pickers (public reminders first).
    class GuildChannelsController < ApplicationController
      before_action :require_service!, except: :index

      # GET /api/v1/guild_channels
      #
      # Text and announcement channels with their category name, ordered as
      # Discord shows them. Not paginated: a guild's channel list is small and
      # pickers need all of it.
      def index
        channels = GuildChannel.text_for_picker.to_a
        render json: { data: GuildChannelResource.new(channels).serializable_hash, meta: { count: channels.size } }
      end

      # POST /api/v1/guild_channels/sync
      #
      # Body: { "data": [ { channel_id, name, channel_type, parent_id, position }, ... ] }
      #
      # Replaces the stored list with the bot's full snapshot in one
      # transaction: channels in the body are upserted, every other row is
      # removed. One invalid entry rejects the whole sync (422) and leaves the
      # old list in place.
      def sync
        entries = params.require(:data)
        raise ActionController::ParameterMissing, "data (array)" unless entries.is_a?(Array)

        rows = entries.map { |entry| channel_attributes(entry) }
        removed = 0
        GuildChannel.transaction do
          rows.each { |row| save_channel!(row) }
          removed = GuildChannel.where.not(channel_id: rows.map { |r| r["channel_id"] }).delete_all
        end

        render json: { data: { synced: rows.size, removed: removed } }
      end

      # PUT /api/v1/guild_channels/:channel_id
      #
      # Body: { "data": { name, channel_type, parent_id, position } }
      #
      # The bot's channelCreate / channelUpdate: inserts the channel (201) or
      # refreshes it (200). The path id wins over any `channel_id` in the body.
      def upsert
        attrs = channel_attributes(params.require(:data)).merge("channel_id" => params[:channel_id].to_s)
        channel, created = save_channel!(attrs)
        render json: { data: GuildChannelResource.new(channel).serializable_hash },
          status: created ? :created : :ok
      end

      # DELETE /api/v1/guild_channels/:channel_id
      #
      # The bot's channelDelete. Idempotent: 204 whether or not the channel was
      # stored, so the bot never has to know what the API holds.
      def destroy
        GuildChannel.where(channel_id: params[:channel_id].to_s).delete_all
        head :no_content
      end

      private

      def channel_attributes(entry)
        raise ActionController::ParameterMissing, "data entry" unless entry.respond_to?(:permit)

        entry.permit(*GuildChannel::WRITABLE).to_h
      end

      # Inserts the channel or refreshes an existing row. Returns the record
      # and whether it was created.
      def save_channel!(attrs)
        channel = GuildChannel.find_or_initialize_by(channel_id: attrs["channel_id"].to_s)
        created = channel.new_record?
        channel.assign_attributes(attrs.except("channel_id"))
        channel.save!
        [ channel, created ]
      end
    end
  end
end
