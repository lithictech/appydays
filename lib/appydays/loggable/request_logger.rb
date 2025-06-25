# frozen_string_literal: true

require "rack"
require "securerandom"

require "appydays/loggable"

##
# Rack middleware for request logging, to replace Rack::CommonLogger.
#
# To get additional log fields, you can subclass this and override +request_tags+.
#
# Or you can use +Appydays::Loggable::RequestLogger.set_request_tags+
# (or call it on your logger subclass) with fields that will accumulate over the request
# and log out in the "request_finished" message.
#
# If you want authenticated user info, make sure you install the middleware
# after your auth middleware.
#
# Params:
#
# error_code: If an unhandled exception reaches the request logger.
#   or happens in the request logger, this status code will be used for easay identification.
#   Generally unhandled exceptions in an application should be handled further downstream,
#   and already be returning the right error code.
# slow_request_seconds: Normally request_finished is logged at info.
#   Requests that take >= this many seconds are logged at warn.
# reraise: Reraise unhandled errors (after logging them).
#   In some cases you may want this to be true, but in some it may bring down the whole process.
class Appydays::Loggable::RequestLogger
  include Appydays::Loggable

  def initialize(app, error_code: 599, slow_request_seconds: 10, reraise: true)
    @app = app
    @error_code = error_code
    @slow_request_seconds = slow_request_seconds
    @reraise = reraise
  end

  def call(env)
    # We need to clear request tags in log_finished, but it's possible it didn't run on the last request
    # so clear the request tags first thing.
    self.class.request_tags.clear
    began_at = Time.now
    request_id = self._ensure_request_id(env)
    # Only use the request_id as the context/correllation id for log messages,
    # otherwise we end up with a lot of log spam.
    status, header, body = SemanticLogger.named_tagged(request_id:) do
      @app.call(env)
    end
    header = Rack::Headers[header]
    body = Rack::BodyProxy.new(body) { self.log_finished(env, began_at, status, header) }
    [status, header, body]
  rescue StandardError => e
    began_at ||= nil
    self.log_finished(env, began_at, 599, {}, e)
    raise if @reraise
  end

  protected def _ensure_request_id(env)
    req_id = env["HTTP_X_REQUEST_ID"] ||= SecureRandom.uuid.to_s
    env["HTTP_TRACE_ID"] ||= req_id
    return req_id
  end

  protected def _request_tags(env, began_at)
    h = {
      request_id: env["HTTP_X_REQUEST_ID"], # Added by _ensure_request_id
      trace_id: env["HTTP_TRACE_ID"], # Legacy purposes
      remote_addr: env["HTTP_X_FORWARDED_FOR"] || env["REMOTE_ADDR"] || "-",
      request_started_at: began_at.to_s,
      request_method: env[Rack::REQUEST_METHOD],
      request_path: env[Rack::PATH_INFO],
      request_query: env.fetch(Rack::QUERY_STRING, "").empty? ? "" : "?#{env[Rack::QUERY_STRING]}",
    }
    h.merge!(self.request_tags(env))
    return h
  end

  def request_tags(_env)
    return {}
  end

  protected def log_finished(env, began_at, status, header, exc=nil)
    elapsed = (Time.now - began_at).to_f
    tags = self._request_tags(env, began_at)
    tags.merge!(
      response_finished_at: Time.now.iso8601,
      response_status: status,
      response_content_length: extract_content_length(header),
      response_ms: elapsed * 1000,
    )
    class_req_tags = self.class.request_tags
    tags.merge!(class_req_tags)
    class_req_tags.clear

    level = if status >= 500
              "error"
    elsif elapsed >= @slow_request_seconds
      "warn"
    else
      "info"
    end

    SemanticLogger.named_tagged(tags) do
      self.logger.send(level, "request_finished", exc)
    end
    SemanticLogger.flush
  end

  protected def extract_content_length(headers)
    value = headers[Rack::CONTENT_LENGTH]
    return !value || value.to_s == "0" ? "-" : value
  end

  # Set request tags that get logged out in the "request_finished" message.
  # This allows you to add useful context to the request without needing
  # a dedicated log message.
  # See README for more info.
  def self.set_request_tags(tags)
    Thread.current[:appydays_request_logger_request_tags] ||= {}
    Thread.current[:appydays_request_logger_request_tags].merge!(tags)
  end

  def self.request_tags = Thread.current[:appydays_request_logger_request_tags] || {}
end
