# frozen_string_literal: true

require "sidekiq"
require "sidekiq/version"
require "sidekiq/job_logger"

require "appydays/loggable"
require "appydays/configurable"

class Appydays::Loggable::SidekiqJobLogger < Sidekiq::JobLogger
  include Appydays::Configurable
  include Appydays::Loggable
  begin
    require "sidekiq/util"
    include Sidekiq::Util
  rescue LoadError
    require "sidekiq/component"
    include Sidekiq::Component
  end

  Sidekiq.logger = self.logger

  def call(item, _queue, &)
    start = self.now
    tags = {
      job_class: item["class"],
      job_id: item["jid"],
      thread_id: self.tid,
    }
    self.with_log_tags(tags) do
      self.call_inner(start, &)
    end
  end

  # Override this to customize when jobs are logged at warn vs. info.
  # We suggest you subclass SidekiqJobLogger, override this method,
  # and return a value that is configured.
  protected def slow_job_seconds
    return 5.0
  end

  protected def call_inner(start)
    yield
    duration = self.elapsed(start)
    log_method = duration >= self.slow_job_seconds ? :warn : :info
    self.logger.send(log_method, "job_done", duration: duration * 1000)
  rescue StandardError
    # Do not log the error since it is probably a sidekiq retry error
    self.logger.error("job_fail", duration: self.elapsed(start) * 1000)
    raise
  end

  protected def elapsed(start)
    (self.now - start).round(3)
  end

  protected def now
    return ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  def self.error_handler(ex, ctx)
    # ctx looks like:
    # {
    # :context=>"Job raised exception",
    # :job=>
    #  {"class"=>"App::Async::FailingJobTester",
    #   "args"=>
    #    [{"id"=>"e8e03571-9851-4daa-a801-a0b43282f317",
    #      "name"=>"app.test_failing_job",
    #      "payload"=>[true]}],
    #   "retry"=>true,
    #   "queue"=>"default",
    #   "jid"=>"cb00c4fe9b2f16b72797d35c",
    #   "created_at"=>1567811837.798969,
    #   "enqueued_at"=>1567811837.79901},
    # :jobstr=>
    #  "{\"class\":\"App::Async::FailingJobTester\", <etc>"
    # }
    job = ctx[:job]
    # If there was a connection error, you may end up with no job context.
    # It's very difficult to test this usefully, so it's not tested.
    unless job
      self.logger.error("job_error_no_job", {}, ex)
      return
    end
    self.logger.error(
      "job_error",
      {
        job_class: job["class"],
        job_args: job["args"],
        job_retry: job["retry"],
        job_queue: job["queue"],
        job_id: job["jid"],
        job_created_at: job["created_at"],
        job_enqueued_at: job["enqueued_at"],
      },
      ex,
    )
  end

  def self.death_handler(job, ex)
    self.logger.error(
      "job_retries_exhausted",
      {
        job_class: job["class"],
        job_args: job["args"],
        job_retry: job["retry"],
        job_queue: job["queue"],
        job_dead: job["dead"],
        job_id: job["jid"],
        job_created_at: job["created_at"],
        job_enqueued_at: job["enqueued_at"],
        job_error_message: job["error_message"],
        job_error_class: job["error_class"],
        job_failed_at: job["failed_at"],
        job_retry_count: job["retry_count"],
      },
      ex,
    )
  end
end
