# frozen_string_literal: true

require "sidekiq"
require "sidekiq/component"
require "sidekiq/job_logger"
require "sidekiq/version"

require "appydays/loggable"
require "appydays/configurable"

class Appydays::Loggable::SidekiqJobLogger < Sidekiq::JobLogger
  include Appydays::Configurable
  include Appydays::Loggable
  include Sidekiq::Component

  # Level to log 'job_done' messages at.
  # Defaults to +:info+.
  attr_accessor :log_level_job_done

  # Level to log slow jobs at.
  # Defaults to +:warn+.
  attr_accessor :log_level_slow_job

  def call(item, _queue, &)
    start = self.now
    self.with_log_tags(job_id: item["jid"]) do
      self.call_inner(item, start, &)
    end
  end

  # Override this to customize when jobs are logged at warn vs. info.
  # We suggest you subclass SidekiqJobLogger, override this method,
  # and return a value that is configured.
  protected def slow_job_seconds
    return 5.0
  end

  protected def call_inner(item, start)
    extra_tags = {job_class: item["class"], thread_id: self.tid}
    yield
    duration = self.elapsed(start)
    log_method = if duration >= self.slow_job_seconds
                   self.log_level_slow_job || :warn
    else
      self.log_level_job_done || :info
    end
    self.logger.send(log_method, "job_done", duration: duration * 1000, **extra_tags, **self.class.job_tags)
  rescue StandardError
    # Do not log the error since it is probably a sidekiq retry error
    self.logger.error("job_fail", duration: self.elapsed(start) * 1000, **extra_tags, **self.class.job_tags)
    raise
  ensure
    self.class.job_tags.clear
  end

  protected def elapsed(start)
    (self.now - start).round(3)
  end

  protected def now
    return ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
  end

  # Set job tags that get logged out in the "job_done" and "job_fail" messages.
  # See README for more info.
  # We do NOT merge the job_tags in with critical errors (death and job_error),
  # since those will log the job args, and they aren't properly tested right now.
  # We may add support in the future.
  def self.set_job_tags(tags)
    Thread.current[:appydays_sidekiq_job_logger_job_tags] ||= {}
    Thread.current[:appydays_sidekiq_job_logger_job_tags].merge!(tags)
  end

  def self.job_tags = Thread.current[:appydays_sidekiq_job_logger_job_tags] || {}

  def self.error_handler(ex, ctx, _config)
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
