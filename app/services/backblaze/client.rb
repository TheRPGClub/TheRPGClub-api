# frozen_string_literal: true

require "base64"
require "digest"
require "faraday"
require "json"
require "uri"

module Backblaze
  class Client
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    AUTHORIZE_URL = "https://api.backblazeb2.com/b2api/v4/b2_authorize_account"
    API_VERSION_PATH = "/b2api/v4"
    RETRYABLE_STATUSES = [ 401, 408, 500, 502, 503, 504 ].freeze
    CACHE_CONTROL = "public, max-age=86400, stale-while-revalidate=604800"

    def self.public_url_for(object_key)
      base_url = ENV.fetch("BACKBLAZE_PUBLIC_BASE_URL", "").to_s.strip
      return if base_url.blank? || object_key.blank?

      encoded_key = object_key.to_s.split("/").map { |part| encode_path_part(part) }.join("/")
      "#{base_url.delete_suffix("/")}/#{encoded_key}"
    end

    def self.encode_path_part(value)
      URI.encode_www_form_component(value.to_s).gsub("+", "%20")
    end

    def upload_bytes(object_key:, bytes:, content_type:)
      raise ConfigurationError, "BACKBLAZE_BUCKET_ID must be set" if bucket_id.blank?

      payload = bytes.to_s.b
      upload_file(object_key: object_key, bytes: payload, content_type: content_type, attempts_remaining: 5)
    end

    def delete_file(object_key:)
      raise ConfigurationError, "BACKBLAZE_BUCKET_ID must be set" if bucket_id.blank?

      file_versions(object_key).map do |file_version|
        delete_file_version(
          file_name: file_version.fetch("fileName"),
          file_id: file_version.fetch("fileId")
        )
      end
    end

    private

    def upload_file(object_key:, bytes:, content_type:, attempts_remaining:)
      upload = upload_url
      response = Faraday.post(upload.fetch("uploadUrl")) do |request|
        request.headers["Authorization"] = upload.fetch("authorizationToken")
        request.headers["X-Bz-File-Name"] = self.class.encode_path_part(object_key)
        request.headers["X-Bz-Content-Sha1"] = Digest::SHA1.hexdigest(bytes)
        request.headers["Content-Type"] = content_type.presence || "b2/x-auto"
        request.headers["Content-Length"] = bytes.bytesize.to_s
        # B2 serves a file with no Cache-Control, ETag or Last-Modified unless
        # told, so browsers refetched every cover on every page. A day, not
        # immutable: an image refresh overwrites the same object key.
        request.headers["X-Bz-Info-b2-cache-control"] = self.class.encode_path_part(CACHE_CONTROL)
        request.body = bytes
        request.options.timeout = 60
      end

      return parse_json_response!(response, "Backblaze upload") if response.success?

      clear_upload_url!
      raise_request_error!(response, "Backblaze upload") unless retryable?(response) && attempts_remaining > 1

      upload_file(
        object_key: object_key,
        bytes: bytes,
        content_type: content_type,
        attempts_remaining: attempts_remaining - 1
      )
    end

    def upload_url
      return @upload_url if @upload_url.present?

      response = Faraday.get("#{api_url}#{API_VERSION_PATH}/b2_get_upload_url") do |request|
        request.headers["Authorization"] = authorization.fetch("authorizationToken")
        request.params["bucketId"] = bucket_id
        request.options.timeout = 20
      end

      @upload_url = parse_json_response!(response, "Backblaze upload URL")
    end

    def file_versions(object_key)
      file_name = object_key.to_s
      file_versions = []
      start_file_name = file_name
      start_file_id = nil

      loop do
        response = Faraday.get("#{api_url}#{API_VERSION_PATH}/b2_list_file_versions") do |request|
          request.headers["Authorization"] = authorization.fetch("authorizationToken")
          request.params["bucketId"] = bucket_id
          request.params["startFileName"] = start_file_name
          request.params["startFileId"] = start_file_id if start_file_id.present?
          request.params["maxFileCount"] = 1_000
          request.options.timeout = 20
        end

        payload = parse_json_response!(response, "Backblaze file version list")
        file_versions.concat(payload.fetch("files", []).select { |file| file["fileName"] == file_name })

        next_file_name = payload["nextFileName"]
        break if next_file_name.blank? || next_file_name != file_name

        start_file_name = next_file_name
        start_file_id = payload["nextFileId"]
      end

      file_versions
    end

    def delete_file_version(file_name:, file_id:)
      response = Faraday.post("#{api_url}#{API_VERSION_PATH}/b2_delete_file_version") do |request|
        request.headers["Authorization"] = authorization.fetch("authorizationToken")
        request.headers["Content-Type"] = "application/json"
        request.body = JSON.generate(fileName: file_name, fileId: file_id)
        request.options.timeout = 20
      end

      parse_json_response!(response, "Backblaze file delete")
    end

    def authorization
      return @authorization if @authorization.present?

      response = Faraday.get(AUTHORIZE_URL) do |request|
        request.headers["Authorization"] = "Basic #{encoded_credentials}"
        request.options.timeout = 20
      end

      @authorization = parse_json_response!(response, "Backblaze authorization")
    end

    def api_url
      authorization.dig("apiInfo", "storageApi", "apiUrl") || authorization.fetch("apiUrl")
    end

    def encoded_credentials
      key_id = ENV.fetch("BACKBLAZE_KEY_ID", "").to_s.strip
      application_key = ENV.fetch("BACKBLAZE_APPLICATION_KEY", "").to_s.strip
      raise ConfigurationError, "BACKBLAZE_KEY_ID must be set" if key_id.blank?
      raise ConfigurationError, "BACKBLAZE_APPLICATION_KEY must be set" if application_key.blank?

      Base64.strict_encode64("#{key_id}:#{application_key}")
    end

    def bucket_id
      ENV.fetch("BACKBLAZE_BUCKET_ID", "").to_s.strip
    end

    def clear_upload_url!
      @upload_url = nil
    end

    def retryable?(response)
      RETRYABLE_STATUSES.include?(response.status)
    end

    def parse_json_response!(response, label)
      payload = JSON.parse(response.body)
      return payload if response.success?

      raise RequestError, "#{label} failed with HTTP #{response.status}: #{error_message(payload)}"
    rescue JSON::ParserError
      raise RequestError, "#{label} failed with HTTP #{response.status}"
    end

    def raise_request_error!(response, label)
      parse_json_response!(response, label)
    end

    def error_message(payload)
      return payload.to_json unless payload.is_a?(Hash)

      payload["message"] || payload["code"] || payload["status"] || payload.to_json
    end
  end
end
