# frozen_string_literal: true

require "appydays/loggable/request_logger"

RSpec.describe Appydays::Loggable::RequestLogger do
  def run_app(app, opts: {}, loggers: [], env: {}, cls: Appydays::Loggable::RequestLogger)
    rl = cls.new(app, **opts, reraise: false)
    return capture_logs_from(loggers << rl.logger, formatter: :json) do
      _, _, body = rl.call(env)
      body&.close
    end
  end

  it "logs info about the request" do
    lines = run_app(proc { [200, {}, ""] })
    expect(lines).to have_a_line_matching(/"message":"request_finished".*"response_status":200/)

    lines = run_app(proc { [400, {}, ""] })
    expect(lines).to have_a_line_matching(/"message":"request_finished".*"response_status":400/)
  end

  it "logs content length" do
    lines = run_app(proc { [200, {"content-LENGTH" => "5"}, ""] })
    expect(lines).to have_a_line_matching(/"response_content_length":"5"/)
  end

  it "logs at 599 (or configured value) if something errors" do
    lines = run_app(proc { raise "testing error" })
    expect(lines).to have_a_line_matching(/"level":"error".*"response_status":599/)
    expect(lines).to have_a_line_matching(/"message":"testing error"/)
  end

  it "logs slow queries at warn" do
    lines = run_app(proc { [200, {}, ""] }, opts: {slow_request_seconds: 0})
    expect(lines).to have_a_line_matching(/"level":"warn".*"response_status":200/)
  end

  it "logs errors at error" do
    lines = run_app(proc { [504, {}, ""] }, opts: {slow_request_seconds: 0})
    expect(lines).to have_a_line_matching(/"level":"error".*"response_status":504/)
  end

  it "adds request_id tag around the execution of the request" do
    logger = SemanticLogger["testlogger"]
    lines = run_app(proc do
      logger.info("check for tags")
      [200, {}, ""]
    end,
                    opts: {slow_request_seconds: 0}, loggers: [logger],)
    expect(lines).to have_attributes(length: 2)
    # This should have request_id, but not the other request tags, like the path
    expect(lines[0]).to include_json(message: "check for tags", context: include("request_id"))
    expect(lines[0]).to include_json(context: not_include("request_path"))
    # This should have all tags
    expect(lines[1]).to include_json(message: "request_finished", context: include("request_id", "request_path"))
  end

  it "adds subclass tags" do
    ReqLogger = Class.new(Appydays::Loggable::RequestLogger) do
      def request_tags(env)
        return {my_header_tag: env["HTTP_MY_HEADER"]}
      end
    end
    lines = run_app(proc { [200, {}, ""] }, env: {"HTTP_MY_HEADER" => "myval"}, cls: ReqLogger)
    expect(lines).to have_a_line_matching(/"my_header_tag":"myval"/)
  end

  it "adds and sets request and trace ids if trace and request headers not set" do
    env = {}
    trace_id = nil
    request_id = nil
    lines = run_app(proc do
      trace_id = env.fetch("HTTP_TRACE_ID")
      request_id = env.fetch("HTTP_X_REQUEST_ID")
      [200, {}, ""]
    end, env:,)
    expect(lines).to contain_exactly(
      include_json(message: "request_finished", context: include(
        "trace_id" => trace_id,
        "request_id" => request_id,
      ),),
    )
  end

  it "reads the request and trace id headers" do
    env = {"HTTP_TRACE_ID" => "t1", "HTTP_X_REQUEST_ID" => "r1"}
    lines = run_app(proc do
      expect(env).to include("HTTP_TRACE_ID" => "t1", "HTTP_X_REQUEST_ID" => "r1")
      [200, {}, ""]
    end, env:,)
    expect(lines).to contain_exactly(
      include_json(message: "request_finished", context: include(
        "trace_id" => "t1",
        "request_id" => "r1",
      ),),
    )
  end

  it "will use the trace id header" do
    env = {"HTTP_TRACE_ID" => "t1"}
    lines = run_app(proc do
      expect(env).to include("HTTP_TRACE_ID" => "t1", "HTTP_X_REQUEST_ID" => have_attributes(length: 36))
      [200, {}, ""]
    end, env:,)
    expect(lines).to contain_exactly(
      include_json(message: "request_finished", context: include(
        "trace_id" => "t1",
        "request_id" => have_attributes(length: 36),
      ),),
    )
  end

  it "can add log fields to the request_finished message" do
    lines = run_app(proc do
      described_class.set_request_tags(abc: "123")
      [200, {}, ""]
    end)
    expect(lines).to contain_exactly(
      include_json(
        level: "info",
        name: "Appydays::Loggable::RequestLogger",
        message: "request_finished",
        context: include("abc" => "123"),
      ),
    )
  end

  it "clears tags after the request (even if it raises an error)" do
    lines = run_app(proc do
      described_class.set_request_tags(tag1: "a")
      [200, {}, ""]
    end)
    expect(lines).to contain_exactly(include_json(context: include("tag1" => "a")))

    lines = run_app(proc do
      described_class.set_request_tags(tag2: "a")
      raise "oops"
    end)
    expect(lines).to contain_exactly(include_json(context: include("tag2" => "a")))
    expect(lines).to contain_exactly(include_json(context: not_include("tag1" => "a")))

    lines = run_app(proc do
      described_class.set_request_tags(tag3: "a")
      [400, {}, ""]
    end)
    expect(lines).to contain_exactly(include_json(context: include("tag3" => "a")))
    expect(lines).to contain_exactly(include_json(context: not_include("tag1" => "a")))
    expect(lines).to contain_exactly(include_json(context: not_include("tag2" => "a")))
  end
end
