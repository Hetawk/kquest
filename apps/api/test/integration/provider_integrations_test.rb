require "test_helper"
require "tempfile"

class ProviderIntegrationsTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:body, :code) do
    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  FakeHttp = Struct.new(:response) do
    attr_reader :last_request

    def request(request)
      @last_request = request
      response
    end
  end

  test "EKDSend receives a server-side transactional email payload" do
    previous_key = ENV["EKDSEND_API_KEY"]
    previous_from = ENV["FROM_EMAIL"]
    ENV["EKDSEND_API_KEY"] = "test-mail-key"
    ENV["FROM_EMAIL"] = "noreply@example.test"
    fake_http = FakeHttp.new(FakeResponse.new({ success: true, messageId: "message-1" }.to_json, "200"))

    with_fake_http(fake_http) do
      result = Integrations::EkdSend::Client.new.send_email(
        to: "educator@example.test",
        subject: "Welcome",
        html: "<p>Hello</p>",
        text: "Hello"
      )

      assert_equal "message-1", result.fetch("messageId")
      assert_equal "Bearer test-mail-key", fake_http.last_request["Authorization"]
      assert_equal "educator@example.test", JSON.parse(fake_http.last_request.body).fetch("to")
      assert_equal "Hello", JSON.parse(fake_http.last_request.body).fetch("text")
    end
  ensure
    ENV["EKDSEND_API_KEY"] = previous_key
    ENV["FROM_EMAIL"] = previous_from
  end

  test "EKDSend failures are raised instead of reported as successful delivery" do
    previous_key = ENV["EKDSEND_API_KEY"]
    ENV["EKDSEND_API_KEY"] = "test-mail-key"
    fake_http = FakeHttp.new(FakeResponse.new({ success: false }.to_json, "503"))

    with_fake_http(fake_http) do
      assert_raises(Integrations::EkdSend::Client::DeliveryError) do
        Integrations::EkdSend::Client.new.send_email(
          to: "educator@example.test",
          subject: "Welcome",
          html: "<p>Hello</p>",
          text: "Hello"
        )
      end
    end
  ensure
    ENV["EKDSEND_API_KEY"] = previous_key
  end

  test "Assets uploads are validated and stored under the signed-in user's namespace" do
    previous_secret = ENV["ASSETS_API_SECRET"]
    ENV["ASSETS_API_SECRET"] = "test-assets-secret"
    user = User.create!(google_uid: SecureRandom.uuid, email: "assets@example.test", name: "Asset User")
    tempfile = Tempfile.new("quest-cover")
    tempfile.binmode
    tempfile.write([ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ].pack("C*"))
    tempfile.write("test image bytes")
    tempfile.rewind
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "cover.png",
      type: "image/png"
    )
    provider_id = SecureRandom.uuid
    provider_path = "/assets/kquest/user-#{user.id}-quests/image/cover.png"
    fake_http = FakeHttp.new(
      FakeResponse.new({ success: true, id: provider_id, public_url: provider_path }.to_json, "201")
    )

    with_fake_http(fake_http) do
      asset = Integrations::EkdAssets::Client.new.upload_cover(user: user, uploaded_file: upload)

      assert_equal provider_id, asset.provider_asset_id
      assert_equal "image/png", asset.content_type
      assert_equal "https://assets.andgroupco.com#{provider_path}", asset.public_url
      assert_includes fake_http.last_request.body, "user-#{user.id}-quests"
      assert_equal "Bearer test-assets-secret", fake_http.last_request["Authorization"]
    end
  ensure
    tempfile&.close!
    ENV["ASSETS_API_SECRET"] = previous_secret
  end

  test "Assets uploads reject unsupported file content before making a provider request" do
    previous_secret = ENV["ASSETS_API_SECRET"]
    ENV["ASSETS_API_SECRET"] = "test-assets-secret"
    user = User.create!(google_uid: SecureRandom.uuid, email: "invalid-assets@example.test", name: "Asset User")
    tempfile = Tempfile.new("quest-cover")
    tempfile.binmode
    tempfile.write("<svg></svg>")
    tempfile.rewind
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: "cover.svg",
      type: "image/svg+xml"
    )

    assert_raises(Integrations::EkdAssets::Client::InvalidUpload) do
      Integrations::EkdAssets::Client.new.upload_cover(user: user, uploaded_file: upload)
    end
    assert_equal 0, UploadedAsset.count
  ensure
    tempfile&.close!
    ENV["ASSETS_API_SECRET"] = previous_secret
  end

  private

  def with_fake_http(fake_http)
    original_start = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.define_method(:start) do |*_arguments, **_keywords, &block|
      block.call(fake_http)
    end
    yield
  ensure
    Net::HTTP.singleton_class.define_method(:start, original_start)
  end
end
