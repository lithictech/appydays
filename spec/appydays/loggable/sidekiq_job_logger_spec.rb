# frozen_string_literal: true

require "appydays/loggable/sidekiq_job_logger"
require "sidekiq/testing"

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

  describe "error_handler" do
    it "handles job errors" do
      ctx = {
        context: "Job raised exception",
        job: {
          "class" => "App::Async::FailingJobTester",
          "args" => [
            {
              "id" => "e8e03571-9851-4daa-a801-a0b43282f317",
              "name" => "app.test_failing_job",
              "payload" => [true],
            },
          ],
          "retry" => true,
          "queue" => "default",
          "jid" => "cb00c4fe9b2f16b72797d35c",
          "created_at" => 1_567_811_837.798969,
          "enqueued_at" => 1_567_811_837.79901,
        },
        jobstr: "{\"class\":\"App::Async::FailingJobTester\", <etc>",
      }
      lines = capture_logs_from(described_class.logger, formatter: :json) do
        described_class.error_handler(RuntimeError.new, ctx, Sidekiq::Config.new)
      end
      expect(lines).to contain_exactly(
        include_json(message: "job_error"),
      )
    end

    it "logs an error if the context is bad" do
      lines = capture_logs_from(described_class.logger, formatter: :json) do
        described_class.error_handler(RuntimeError.new, {}, Sidekiq::Config.new)
      end
      expect(lines).to contain_exactly(
        include_json(message: "job_error_no_job"),
      )
    end
  end

  describe "death_handler" do
    it "handles job deaths" do
      job = {
        "class" => "App::Async::FailingJobTester",
        "jid" => "cb00c4fe9b2f16b72797d35c",
        "created_at" => 1_567_811_837.798969,
        "enqueued_at" => 1_567_811_837.79901,
      }
      lines = capture_logs_from(described_class.logger, formatter: :json) do
        described_class.death_handler(job, RuntimeError.new)
      end
      expect(lines).to contain_exactly(
        include_json(message: "job_retries_exhausted"),
      )
    end
  end
end
