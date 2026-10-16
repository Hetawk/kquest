require "test_helper"

class ApiHealthTest < ActionDispatch::IntegrationTest
  test "returns the versioned API health response" do
    get "/api/v1/health"

    assert_response :success
    assert_equal(
      { "data" => { "status" => "ok", "api_version" => "v1" } },
      response.parsed_body
    )
  end
end
