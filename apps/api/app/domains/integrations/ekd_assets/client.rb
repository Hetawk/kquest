require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

module Integrations
  module EkdAssets
    class Client
      class UploadError < StandardError; end
      class InvalidUpload < UploadError; end

      MIME_EXTENSIONS = {
        "image/jpeg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp"
      }.freeze

      def upload_cover(user:, uploaded_file:)
        secret = ENV["ASSETS_API_SECRET"].to_s
        raise UploadError, "ASSETS_API_SECRET is not configured." if secret.blank?
        unless uploaded_file.is_a?(ActionDispatch::Http::UploadedFile)
          raise InvalidUpload, "Choose one image file to upload."
        end

        content_type = sniff_content_type(uploaded_file)
        raise InvalidUpload, "Upload a valid PNG, JPEG, or WebP image." unless content_type
        if uploaded_file.size <= 0 || uploaded_file.size > 5.megabytes
          raise InvalidUpload, "Cover images must be between 1 byte and 5 MB."
        end

        uri = upload_uri
        boundary = "----kquest#{SecureRandom.hex(16)}"
        bytes = uploaded_file.tempfile.tap(&:rewind).read
        body = multipart_body(
          boundary: boundary,
          filename: "cover.#{MIME_EXTENSIONS.fetch(content_type)}",
          content_type: content_type,
          bytes: bytes,
          user: user
        )
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{secret}"
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = body

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 30,
          write_timeout: 30
        ) { |http| http.request(request) }
        result = JSON.parse(response.body)
        unless response.is_a?(Net::HTTPSuccess) && result["success"] == true
          raise UploadError, "EKD Digital Assets rejected the upload (HTTP #{response.code})."
        end

        asset_id = result["id"].to_s
        public_path = result["public_url"].to_s
        unless asset_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i) &&
            safe_public_path?(public_path, user)
          raise UploadError, "EKD Digital Assets returned incomplete asset metadata."
        end

        UploadedAsset.create!(
          user: user,
          provider_asset_id: asset_id,
          public_url: "#{uri.origin}#{public_path}",
          content_type: content_type,
          file_size: uploaded_file.size
        )
      rescue JSON::ParserError
        raise UploadError, "EKD Digital Assets returned an invalid response."
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise UploadError, "EKD Digital Assets could not be reached (#{error.class})."
      end

      private

      def sniff_content_type(file)
        file.tempfile.tap(&:rewind)
        header = file.tempfile.read(12).bytes
        file.tempfile.rewind
        return "image/png" if header.take(4) == [ 0x89, 0x50, 0x4e, 0x47 ]
        return "image/jpeg" if header.take(3) == [ 0xff, 0xd8, 0xff ]
        if header.take(4) == [ 0x52, 0x49, 0x46, 0x46 ] && header[8, 4] == [ 0x57, 0x45, 0x42, 0x50 ]
          return "image/webp"
        end

        nil
      end

      def upload_uri
        uri = URI.parse(ENV.fetch("ASSETS_API_URL", "https://assets.andgroupco.com/api/v1"))
        unless %w[https http].include?(uri.scheme) && uri.host && uri.userinfo.nil? &&
            uri.query.nil? && uri.fragment.nil?
          raise UploadError, "ASSETS_API_URL must be an HTTP(S) URL without credentials."
        end
        if uri.scheme != "https" && !Rails.env.development? && !Rails.env.test?
          raise UploadError, "ASSETS_API_URL must use HTTPS outside development."
        end

        api_path = uri.path.sub(%r{/+\z}, "")
        uri.path = if api_path.end_with?("/api/v1/assets")
          "#{api_path}/upload"
        elsif api_path.end_with?("/api/v1")
          "#{api_path}/assets/upload"
        else
          "#{api_path}/api/v1/assets/upload"
        end
        uri
      rescue URI::InvalidURIError
        raise UploadError, "ASSETS_API_URL is invalid."
      end

      def multipart_body(boundary:, filename:, content_type:, bytes:, user:)
        [
          "--#{boundary}\r\n",
          "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
          "Content-Type: #{content_type}\r\n\r\n",
          bytes,
          "\r\n--#{boundary}\r\n",
          "Content-Disposition: form-data; name=\"client_id\"\r\n\r\nkquest",
          "\r\n--#{boundary}\r\n",
          "Content-Disposition: form-data; name=\"project_name\"\r\n\r\nuser-#{user.id}-quests",
          "\r\n--#{boundary}\r\n",
          "Content-Disposition: form-data; name=\"asset_type\"\r\n\r\nimage",
          "\r\n--#{boundary}--\r\n"
        ].join
      end

      def safe_public_path?(path, user)
        namespace = "/assets/kquest/user-#{user.id}-quests/image/"
        return false unless path.start_with?(namespace)

        uri = URI.parse(path)
        uri.host.nil? && uri.query.nil? && uri.fragment.nil? &&
          uri.path.split("/").none? { |segment| segment == "." || segment == ".." || segment.include?("%") }
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
