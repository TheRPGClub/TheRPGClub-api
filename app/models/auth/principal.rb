# frozen_string_literal: true

module Auth
  class Principal
    attr_reader :kind, :id, :discord_id, :username, :global_name, :avatar, :email
    # The member's row as auth read it this request (without image bytes), so
    # role gates and GET /session don't read it again. nil when the principal
    # was rebuilt from a cookie session; never serialized.
    attr_reader :user

    def initialize(kind:, id:, discord_id: nil, username: nil, global_name: nil, avatar: nil, email: nil,
                   is_dev: false, is_longstanding: false, user: nil)
      @kind = kind.to_s
      @id = id.to_s
      @discord_id = discord_id&.to_s
      @username = username
      @global_name = global_name
      @avatar = avatar
      @email = email
      @is_dev = is_dev ? true : false
      @is_longstanding = is_longstanding ? true : false
      @user = user
    end

    def self.service
      new(kind: "service", id: "discord_bot")
    end

    # The versioning job (ticket api#514): may only report Pending Changes.
    def self.release
      new(kind: "release", id: "release")
    end

    def self.discord_user(user, discord_payload = {}, is_dev: false, is_longstanding: false)
      new(
        kind: "discord_user",
        id: user.user_id,
        discord_id: user.user_id,
        username: discord_payload["username"] || user.username,
        global_name: discord_payload["global_name"] || user.global_name,
        avatar: discord_payload["avatar"],
        email: discord_payload["email"],
        is_dev: is_dev,
        is_longstanding: is_longstanding,
        user: user
      )
    end

    def self.from_session(payload)
      return if payload.blank?

      new(
        kind: payload["kind"],
        id: payload["id"],
        discord_id: payload["discord_id"],
        username: payload["username"],
        global_name: payload["global_name"],
        avatar: payload["avatar"],
        email: payload["email"],
        is_dev: payload["is_dev"],
        is_longstanding: payload["is_longstanding"]
      )
    end

    def to_session
      {
        "kind" => kind,
        "id" => id,
        "discord_id" => discord_id,
        "username" => username,
        "global_name" => global_name,
        "avatar" => avatar,
        "email" => email,
        "is_dev" => dev?,
        "is_longstanding" => longstanding?
      }
    end

    def service?
      kind == "service"
    end

    def discord_user?
      kind == "discord_user"
    end

    def release?
      kind == "release"
    end

    def dev?
      @is_dev == true
    end

    def longstanding?
      @is_longstanding == true
    end

    def as_json(*)
      to_session.except("email", "is_dev", "is_longstanding")
        .merge("service" => service?, "dev" => dev?, "longstanding" => longstanding?)
    end
  end
end
