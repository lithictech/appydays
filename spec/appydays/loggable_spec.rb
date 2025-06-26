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
      # Error format is different between Ruby versions
      expect(lines[0]).to match(%r{:in .*generate_stack_trace'","skipped \d\d\d frames","/})
      expect(lines[0]).to have_attributes(length: be_between(600, 900))
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
end
