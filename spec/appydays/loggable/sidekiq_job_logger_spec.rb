# frozen_string_literal: true

require "appydays/loggable/sidekiq_job_logger"

RSpec.describe Appydays::Loggable::SidekiqJobLogger do
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

  let(:logger) { logcls.new(Sidekiq::Config.new) }

  def log(reraise: true, &block)
    block ||= proc {}
    lines = capture_logs_from(logcls.logger, formatter: :json) do
      logger.call({}, nil) do
        block.call
      end
    rescue StandardError => e
      raise e if reraise
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
    lines = log(reraise: false) do
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

  it "can add log fields to the job_done message" do
    lines = log do
      described_class.set_job_tags(tag1: "hi")
    end
    expect(lines).to contain_exactly(
      include_json(
        level: "info",
        name: "TestLogger",
        message: "job_done",
        context: include("tag1" => "hi"),
      ),
    )
  end

  it "can add log fields to the job_fail message" do
    lines = log(reraise: false) do
      described_class.set_job_tags(tag1: "hi")
      raise "hello"
    end
    expect(lines).to contain_exactly(
      include_json(
        level: "error",
        name: "TestLogger",
        message: "job_fail",
        context: include("tag1" => "hi"),
      ),
    )
  end

  it "clears job tags after the job" do
    lines = log do
      described_class.set_job_tags(tag1: "hi")
    end
    expect(lines).to contain_exactly(
      include_json(
        context: include("tag1" => "hi"),
      ),
    )

    lines = log
    expect(lines).to contain_exactly(
      include_json(
        context: not_include("tag1"),
      ),
    )
  end
end
