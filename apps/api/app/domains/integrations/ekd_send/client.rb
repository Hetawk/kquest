require "json"
require "net/http"
require "openssl"
require "uri"

module Integrations
  module EkdSend
    class Client
      class DeliveryError < StandardError; end

      def send_email(to:, subject:, html:, text:)
        api_key = ENV["EKDSEND_API_KEY"].to_s
        raise DeliveryError, "EKDSEND_API_KEY is not configured." if api_key.blank?

        uri = api_uri
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(
          type: "email",
          to: to,
          from: ENV["FROM_EMAIL"].presence || "noreply@ekddigital.com",
          subject: subject,
          body: html,
          text: text
        )

        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 15,
          write_timeout: 15
        ) { |http| http.request(request) }

        result = JSON.parse(response.body)
        return result if response.is_a?(Net::HTTPSuccess) && result["success"] == true

        raise DeliveryError, "EKDSend rejected the message (HTTP #{response.code})."
      rescue JSON::ParserError
        raise DeliveryError, "EKDSend returned an invalid response."
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
        raise DeliveryError, "EKDSend could not be reached (#{error.class})."
      end

      private

      def api_uri
        uri = URI.parse(ENV.fetch("EKDSEND_API_URL", "https://es.ekddigital.com/api/v1"))
        unless %w[https http].include?(uri.scheme) && uri.host && uri.userinfo.nil? &&
            uri.query.nil? && uri.fragment.nil?
          raise DeliveryError, "EKDSEND_API_URL must be an HTTP(S) URL without credentials."
        end
        if uri.scheme != "https" && !Rails.env.development? && !Rails.env.test?
          raise DeliveryError, "EKDSEND_API_URL must use HTTPS outside development."
        end

        uri.path = "#{uri.path.sub(%r{/+\z}, "")}/send"
        uri
      rescue URI::InvalidURIError
        raise DeliveryError, "EKDSEND_API_URL is invalid."
      end
    end
  end
end
