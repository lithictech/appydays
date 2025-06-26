# frozen_string_literal: true

require "appydays/loggable/httparty_formatter"

RSpec.describe "HTTParty formatter" do
  it "logs structured request information" do
    logger = SemanticLogger["http_spec_logging_test"]
    stub_request(:post, "https://foo/bar").to_return(status: 200, body: "")
    logs = capture_logs_from(logger, formatter: :json) do
      HTTParty.post("https://foo/bar", body: {x: 1}, logger:, log_format: :appydays)
    end
    expect(logs).to contain_exactly(
      include_json(
        "message" => "httparty_request",
        "level" => "info",
        "context" => include("http_method" => "POST"),
      ),
    )
  end
end
