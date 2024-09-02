# frozen_string_literal: true

require "appydays/loggable/request_logger"
require "appydays/loggable/sidekiq_job_logger"
require "appydays/loggable/sequel_logger"
require "appydays/loggable/httparty_formatter"
require "httparty"
require "sequel"

RSpec.describe Appydays::Loggable do
  it "can set the default log level" do
    expect(SemanticLogger).to receive(:default_level=).with("trace")
    described_class.default_level = "trace"
  end

  it "can look up the logger for an object for a non-Loggable" do
    cls = Class.new
    cls_logger = described_class[cls]
    inst_logger = described_class[cls.new]
    expect(cls_logger).to be_a(SemanticLogger::Logger)
    expect(inst_logger).to be_a(SemanticLogger::Logger)
    expect(cls_logger.name).to eq(inst_logger.name)
  end

  it "can look up the logger for an object for a Loggable" do
    cls = Class.new do
      include Appydays::Loggable
    end
    cls_logger = described_class[cls]
    inst = cls.new
    inst_logger = described_class[inst]
    expect(cls_logger).to be(inst_logger)
    expect(cls.logger).to be(inst.logger)
  end

  it "adds logger methods" do
    cls = Class.new do
      include Appydays::Loggable
    end
    inst = cls.new
    expect(cls.logger).to be_a(SemanticLogger::Logger)
    expect(inst.logger).to be_a(SemanticLogger::Logger)
  end

  describe "custom formatting" do
    it "combines :payload, :tags, and :named_tags into :context" do
      logger1 = described_class["spec-helper-test"]

      lines = capture_logs_from(logger1, formatter: :json) do
        SemanticLogger.tagged("tag1", "tag2") do
          SemanticLogger.named_tagged(nt1: 1, nt2: 2) do
            logger1.error("hello", opt1: 1, opt2: 2)
          end
        end
      end
      j = JSON.parse(lines[0])
      expect(j).to include("context")
      expect(j["context"]).to eq(
        "_tags" => ["tag1", "tag2"],
        "nt1" => 1,
        "nt2" => 2,
        "opt1" => 1,
        "opt2" => 2,
      )
    end
  end

  describe ":json_trunc format" do
    let(:logger1) { described_class["spec-helper-test"] }
    let(:long_str) { "a" * 200 }
    let(:opts) do
      {
        long: long_str,
        short: "abc",
        n: 5,
        array: [long_str, "abc", 5, [long_str, "abc"]],
        obj: {long: long_str, n: 5},
      }
    end

    it "will not trim if the payload is small enough" do
      lines = capture_logs_from(logger1, formatter: :json_trunc) do
        logger1.info("hello", opts)
      end
      expect(lines[0]).to have_attributes(length: be_between(1100, 1130))
    end

    it "will trim large strings if the payload is too large" do
      lines = capture_logs_from(logger1, formatter: :json_trunc) do
        SemanticLogger.appenders.first.formatter.truncate_at(100, 5)
        logger1.info("hello", opts)
      end
      expect(lines[0]).to have_attributes(length: be_between(300, 350))
    end

    def generate_stack_trace(i=0)
      raise "recursed!" if i > 400
      generate_stack_trace(i + 1)
    end

    it "will fold in stack traces" do
      lines = capture_logs_from(logger1, formatter: :json_trunc) do
        generate_stack_trace
      rescue RuntimeError => e
        logger1.info("hello", e)
      end
      expect(lines[0]).to match(%r{:in `generate_stack_trace'","skipped \d\d\d frames","/})
      expect(lines[0]).to have_attributes(length: be_between(680, 730))
    end

    it "ignores non-array stack_trace keys" do
      lines = capture_logs_from(logger1, formatter: :json_trunc) do
        logger1.info("hello", stack_trace: long_str * 3)
      end
      expect(lines[0]).to include("{\"stack_trace\":\"aaaaaaaa")
      expect(lines[0]).to have_attributes(length: be_between(800, 900))
    end
  end

  describe "#with_log_tags" do
    logger = SemanticLogger[Kernel]

    it "adds log tags to SemanticLogger" do
      logs = capture_logs_from(logger) do
        blockresult = described_class.with_log_tags(x: 1) do
          logger.warn("hi")
          5
        end
        expect(blockresult).to eq(5)
      end
      expect(logs).to(contain_exactly(include("{x: 1} Kernel -- hi")))
    end

    begin
      require "sentry-ruby"

      describe "with Sentry available" do
        it "adds log tags to Sentry" do
          scope = Sentry::Scope.new
          expect(Sentry).to receive(:configure_scope).and_yield(scope)

          expect(described_class.with_log_tags(x: 1) { 5 }).to eq(5)
          expect(scope.instance_variable_get(:@extra)).to eq(x: 1)
        end
      end
    rescue LoadError
      nil
    end
  end

  describe "spec helpers" do
    logger1 = described_class["spec-helper-test"]

    it "can capture log lines to a logger" do
      lines = capture_logs_from(logger1) do
        logger1.error("hello there")
      end
      expect(lines).to have_a_line_matching(/hello there/)
    end

    it "can capture log lines to multiple loggers" do
      lines = capture_logs_from(logger1) do
        logger1.error("hello there")
      end
      expect(lines).to have_a_line_matching(/hello there/)
    end

    it "can filter logs below a level" do
      lines = capture_logs_from(logger1, level: :error) do
        logger1.warn("hello there")
      end
      expect(lines).to be_empty
    end

    it "can specify the formatter" do
      lines = capture_logs_from(logger1, formatter: :json) do
        logger1.warn("hello there")
      end
      expect(lines).to have_a_line_matching(/"message":"hello there"/)

      lines = capture_logs_from(logger1, formatter: :color) do
        logger1.warn("hello there")
      end
      expect(lines).to have_a_line_matching(/-- hello there/)
    end

    it "sets and restores the level of all appenders" do
      logger1.level = :info
      other_appender = SemanticLogger.add_appender(io: StringIO.new, level: :trace)
      capture_logs_from(logger1, level: :trace) do
        expect(logger1.level).to eq(:trace)
        expect(other_appender.level).to eq(:fatal)
      end
      expect(logger1.level).to eq(:info)
      expect(other_appender.level).to eq(:trace)
      SemanticLogger.remove_appender(other_appender)
    end
  end

  describe Appydays::Loggable::RequestLogger do
    def run_app(app, opts: {}, loggers: [], env: {}, cls: Appydays::Loggable::RequestLogger)
      rl = cls.new(app, **opts.merge(reraise: false))
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

    it "adds tags around the execution of the request" do
      logger = SemanticLogger["testlogger"]
      lines = run_app(proc do
                        logger.info("check for tags")
                        [200, {}, ""]
                      end,
                      opts: {slow_request_seconds: 0}, loggers: [logger],)
      expect(lines).to have_a_line_matching(/"message":"check for tags".*"request_method":/)
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

    it "adds a request id" do
      lines = run_app(proc { [200, {}, ""] })
      expect(lines).to have_a_line_matching(/"request_id":"[0-9a-z]{8}-/)
    end

    it "reads a trace id from headers" do
      lines = run_app(proc { [200, {}, ""] }, env: {"HTTP_TRACE_ID" => "123xyz"})
      expect(lines).to have_a_line_matching(/"trace_id":"123xyz"/)
    end

    it "sets the trace ID header if not set" do
      env = {}
      lines = run_app(proc do
        expect(env).to(include("HTTP_TRACE_ID"))
        [200, {}, ""]
      end, env:,)
      expect(lines).to have_a_line_matching(/"trace_id":"[0-9a-z]{8}-/)
    end
  end

  describe Appydays::Loggable::SidekiqJobLogger, :db do
    before(:each) { @slow_secs = 5 }
    let(:logcls) do
      slow_secs = @slow_secs
      Class.new(Appydays::Loggable::SidekiqJobLogger) do
        attr_accessor :slow_secs

        def self.name
          return "TestLogger"
        end
        define_method(:slow_job_seconds) { slow_secs }
      end
    end

    let(:logger) { logcls.new }

    def log(&block)
      block ||= proc {}
      lines = capture_logs_from(logcls.logger, formatter: :json) do
        logger.call({}, nil) do
          block.call
        end
      rescue StandardError => e
        nil
      end
      return lines
    end

    it "logs a info message for the job" do
      lines = log
      expect(lines).to contain_exactly(
        include_json(
          level: "info",
          name: "TestLogger",
          message: "job_done",
          duration_ms: be_a(Numeric),
        ),
      )
    end

    it "logs duration properly (SemanticLogger uses milliseconds)" do
      lines = log { sleep(0.001) }
      expect(lines).to contain_exactly(
        include_json(
          message: "job_done",
          duration: match(/^\d+\.\d+ms$/),
          duration_ms: be >= 1,
        ),
      )
    end

    it "logs at warn if the time taken is more than the slow job seconds" do
      @slow_secs = 0
      lines = log
      expect(lines).to contain_exactly(
        include_json(
          level: "warn",
          name: "TestLogger",
          message: "job_done",
          duration_ms: be_a(Numeric),
        ),
      )
    end

    it "logs at error (but does not log the exception) if the job fails" do
      lines = log do
        1 / 0
      end

      expect(lines).to contain_exactly(
        include_json(
          level: "error",
          name: "TestLogger",
          message: "job_fail",
          duration_ms: be_a(Numeric),
        ),
      )
      expect(lines[0]).to_not include("exception")
    end
  end

  describe "Sequel Logging" do
    after(:each) do
      Sequel::Database::AppydaysLogger.setdefaults
    end
    describe "with structure logging" do
      def log
        logger = SemanticLogger[Sequel]
        db = Sequel.connect("mock://", logger:, log_warn_duration: 3)
        return capture_logs_from(logger, formatter: :json) do
          yield(db)
        end
      end

      it "logs info" do
        lines = log do |db|
          db.log_info("hello1")
          db.log_info("hello2", {x: 1})
        end
        expect(lines).to contain_exactly(
          include_json(
            level: "info",
            name: "Sequel",
            message: "sequel_log",
            context: {"message" => "hello1"},
          ),
          include_json(
            context: {"message" => "hello2", "args" => {"x" => 1}},
          ),
        )
      end

      it "logs exceptions" do
        lines = log do |db|
          db.log_exception(RuntimeError.new("nope"), "msg")
        end
        expect(lines).to contain_exactly(
          include_json(
            level: "error",
            message: "sequel_exception",
            exception: {"name" => "RuntimeError", "message" => "nope", "stack_trace" => nil},
            context: {"sequel_message" => "msg"},
          ),
        )
      end

      it "logs 'table exists' exceptions at debug" do
        lines = log do |db|
          db.log_exception(RuntimeError.new("nope"), "SELECT NULL AS nil FROM sch.foobar LIMIT 1")
          db.log_exception(RuntimeError.new("nope"), "select null as \"nil\" FROM \"sch\".\"foobar\" LIMIT 1")
        end
        expect(lines).to contain_exactly(
          include_json(level: "debug", message: "sequel_exception"),
          include_json(level: "debug", message: "sequel_exception"),
        )
      end

      it "logs duration" do
        lines = log do |db|
          db.log_duration(4, "slow")
          db.log_duration(1, "fast")
        end
        expect(lines).to contain_exactly(
          include_json(
            level: "warn",
            message: "sequel_query",
            duration_ms: 4000,
            duration: "4.000s",
            context: {"query" => "slow"},
          ),
          include_json(
            level: "info",
            message: "sequel_query",
            context: {"query" => "fast"},
          ),
        )
      end

      it "truncates long messages at debug" do
        Sequel::Database::AppydaysLogger.truncation_context = 3
        Sequel::Database::AppydaysLogger.truncation_message = "<truncated>"
        Sequel::Database::AppydaysLogger.log_full_message_level = :debug

        lines = log do |db|
          db.log_duration(4, "a" * 3000)
          db.log_duration(1, "a" * 3000)
        end

        expect(lines).to contain_exactly(
          include_json(
            level: "warn",
            message: "sequel_query",
            context: {"query" => "aaa<truncated>aaa", "truncated" => true},
          ),
          include_json(
            level: "debug",
            message: "sequel_query_debug",
            context: {"query" => have_length(3000)},
          ),
          include_json(
            level: "info",
            message: "sequel_query",
            context: {"query" => "aaa<truncated>aaa", "truncated" => true},
          ),
          include_json(
            level: "debug",
            message: "sequel_query_debug",
            context: {"query" => have_length(3000)},
          ),
        )
      end

      it "does not log untruncated messages if log_full_message_level is nil" do
        Sequel::Database::AppydaysLogger.truncation_context = 3
        Sequel::Database::AppydaysLogger.truncation_message = "<truncated>"
        Sequel::Database::AppydaysLogger.log_full_message_level = nil

        lines = log do |db|
          db.log_duration(4, "a" * 3000)
          db.log_duration(1, "a" * 3000)
        end

        expect(lines).to contain_exactly(
          include_json(
            level: "warn",
            message: "sequel_query",
            context: {"query" => "aaa<truncated>aaa", "truncated" => true},
          ),
          include_json(
            level: "info",
            message: "sequel_query",
            context: {"query" => "aaa<truncated>aaa", "truncated" => true},
          ),
        )
      end
    end

    describe "with standard logging" do
      def log
        device = StringIO.new
        logger = Logger.new(device)
        db = Sequel.connect("mock://", logger:, log_warn_duration: 3)
        yield(db)
        return device.string
      end

      it "logs info" do
        lines = log do |db|
          db.log_info("hello1")
          db.log_info("hello2", {x: 1})
        end
        expect(lines.lines).to contain_exactly(
          include("INFO -- : hello1\n"),
          include("INFO -- : hello2; {:x=>1}"),
        )
      end

      it "logs exceptions" do
        lines = log do |db|
          db.log_exception(RuntimeError.new("nope"), "msg")
        end
        expect(lines.lines).to contain_exactly(
          include("ERROR -- : RuntimeError: nope: msg\n"),
        )
      end

      it "logs duration" do
        lines = log do |db|
          db.log_duration(4, "slow")
          db.log_duration(1, "fast")
        end
        expect(lines.lines).to contain_exactly(
          include("INFO -- : (1.000000s) fast\n"),
          include("WARN -- : (4.000000s) slow\n"),
        )
      end
    end
  end

  describe "HTTParty formatter" do
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
end
