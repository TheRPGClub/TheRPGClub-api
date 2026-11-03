# frozen_string_literal: true

# Serializes a GuildChannel. `category_name` is the parent category's name,
# present when the record was loaded through GuildChannel.text_for_picker and
# null otherwise (or when the channel has no category).
class GuildChannelResource
  include BaseResource

  attributes :channel_id, :name, :channel_type, :parent_id, :position

  attribute :category_name do |channel|
    channel.has_attribute?(:category_name) ? channel[:category_name] : nil
  end
end
