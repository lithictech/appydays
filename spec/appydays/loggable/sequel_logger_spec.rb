# frozen_string_literal: true

require "appydays/loggable/sequel_logger"

RSpec.describe "Sequel Logging" do
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
      tags = "{x: 1}"
      tags = "{:x=>1}" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4.0")
      expect(lines.lines).to contain_exactly(
        include("INFO -- : hello1\n"),
        include("INFO -- : hello2; #{tags}"),
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
