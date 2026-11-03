# frozen_string_literal: true

require "rails_helper"

# A Superadmin makes the bot say something (web parity 2, #337), as the
# bot's `/superadmin say` does: a message in a synced text channel, or a
# reply to a message in it. The bot posts it as a `say` bot job that allows
# plain user mentions only, never @everyone, @here or roles.
RSpec.describe "api/v1/bot_say behavior", type: :request do
  let(:superadmin) { create(:user) }
  let(:superadmin_headers) { auth_headers_for(superadmin, is_dev: true) }
  let!(:channel) { create(:guild_channel, channel_id: "111", name: "general") }

  before { stub_const("ENV", ENV.to_h.merge("DISCORD_RPGCLUB_GUILD_ID" => "999")) }

  def say(data, headers: superadmin_headers)
    post "/api/v1/bot_say", params: { data: data }, headers: headers, as: :json
  end

  refused_callers = {
    "a plain member" => {},
    "a Members role holder" => { role_member: true },
    "a Regulars role holder" => { role_regular: true },
    "a Moderator" => { role_moderator: true },
    "an Admin" => { role_admin: true }
  }

  describe "POST /api/v1/bot_say" do
    it "queues a say job for the channel, allowing user mentions only" do
      say({ channel_id: "111", content: "  Hello <@42>, welcome! @everyone  " })

      expect(response).to have_http_status(:accepted)
      job = BotJob.sole
      expect(job).to have_attributes(
        kind: "say", status: "queued", requested_by_user_id: superadmin.user_id,
        summary: 'Say in #general: "Hello <@42>, welcome! @everyone"',
        payload: {
          "channel_id" => "111", "content" => "Hello <@42>, welcome! @everyone", "reply_to" => nil,
          "allowed_mentions" => { "parse" => [ "users" ] }
        }
      )
      expect(json.fetch("data")).to include("id" => job.id, "kind" => "say", "status" => "queued")
      expect(json.fetch("data")).not_to have_key("payload")
    end

    it "keeps the content's line breaks" do
      say({ channel_id: "111", content: "Line one\nLine two" })

      expect(BotJob.sole.payload.fetch("content")).to eq("Line one\nLine two")
    end

    it "cuts a long content in the summary but not in the payload" do
      content = "word " * 100
      say({ channel_id: "111", content: content })

      job = BotJob.sole
      expect(job.payload.fetch("content")).to eq(content.strip)
      expect(job.summary).to eq("Say in #general: \"#{('word ' * 16).strip}...\"")
    end

    it "replies to a message link in the channel" do
      say({ channel_id: "111", content: "Agreed",
        reply_to_message_link: "https://discord.com/channels/999/111/222333" })

      expect(response).to have_http_status(:accepted)
      expect(BotJob.sole).to have_attributes(
        summary: 'Reply in #general: "Agreed"',
        payload: include("channel_id" => "111", "reply_to" => { "channel_id" => "111", "message_id" => "222333" })
      )
    end

    it "accepts ptb, canary and discordapp links and ignores a blank link" do
      %w[https://ptb.discord.com/channels/999/111/5 https://canary.discord.com/channels/999/111/6
         https://discordapp.com/channels/999/111/7].each do |link|
        say({ channel_id: "111", content: "hi", reply_to_message_link: link })
        expect(response).to have_http_status(:accepted)
      end
      say({ channel_id: "111", content: "hi", reply_to_message_link: " " })

      expect(BotJob.order(:id).map { |job| job.payload.dig("reply_to", "message_id") }).to eq([ "5", "6", "7", nil ])
    end

    it "lets the service queue one with no requester" do
      say({ channel_id: "111", content: "hi" }, headers: service_headers)

      expect(response).to have_http_status(:accepted)
      expect(BotJob.sole.requested_by_user_id).to be_nil
    end

    {
      "an unknown channel" => { channel_id: "404", content: "hi" },
      "a channel that is not a text channel" => { channel_id: "112", content: "hi" },
      "no channel" => { content: "hi" },
      "blank content" => { channel_id: "111", content: "   " },
      "content over 2000 characters" => { channel_id: "111", content: "a" * 2001 },
      "a link that is not a message link" => { channel_id: "111", content: "hi",
                                               reply_to_message_link: "https://example.com/channels/9/111/5" },
      "a link to a channel with no message" => { channel_id: "111", content: "hi",
                                                 reply_to_message_link: "https://discord.com/channels/999/111" },
      "a link to a message in another channel" => { channel_id: "111", content: "hi",
                                                    reply_to_message_link: "https://discord.com/channels/999/777/5" }
    }.each do |label, data|
      it "422s for #{label}, queueing nothing" do
        create(:guild_channel, channel_id: "112", channel_type: 2)

        say(data)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.fetch("error")).to be_a(String)
        expect(BotJob.count).to eq(0)
      end
    end

    it "422s for a link to another guild" do
      say({ channel_id: "111", content: "hi", reply_to_message_link: "https://discord.com/channels/998/111/5" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(BotJob.count).to eq(0)
    end

    it "takes a link to any guild when the club's guild is not configured" do
      stub_const("ENV", ENV.to_h.except("DISCORD_RPGCLUB_GUILD_ID"))

      say({ channel_id: "111", content: "hi", reply_to_message_link: "https://discord.com/channels/998/111/5" })

      expect(response).to have_http_status(:accepted)
    end

    it "401s without a session" do
      say({ channel_id: "111", content: "hi" }, headers: {})

      expect(response).to have_http_status(:unauthorized)
      expect(BotJob.count).to eq(0)
    end

    refused_callers.each do |label, flags|
      it "403s for #{label}" do
        say({ channel_id: "111", content: "hi" }, headers: auth_headers_for(create(:user, **flags)))

        expect(response).to have_http_status(:forbidden)
        expect(BotJob.count).to eq(0)
      end
    end
  end
end
