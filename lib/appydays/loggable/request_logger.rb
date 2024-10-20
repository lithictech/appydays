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
    request_fields = self._request_tags(env, began_at)
    status, header, body = SemanticLogger.named_tagged(request_fields) { @app.call(env) }
    header = Rack::Utils::HeaderHash.new(header)
    body = Rack::BodyProxy.new(body) { self.log_finished(request_fields, began_at, status, header) }
    [status, header, body]
  rescue StandardError => e
    began_at ||= nil
    request_fields ||= {}
    self.log_finished(request_fields, began_at, 599, {}, e)
    raise if @reraise
  end

  protected def _request_tags(env, began_at)
    req_id = SecureRandom.uuid.to_s
    env["HTTP_TRACE_ID"] ||= req_id
    h = {
      remote_addr: env["HTTP_X_FORWARDED_FOR"] || env["REMOTE_ADDR"] || "-",
      request_started_at: began_at.to_s,
      request_method: env[Rack::REQUEST_METHOD],
      request_path: env[Rack::PATH_INFO],
      request_query: env.fetch(Rack::QUERY_STRING, "").empty? ? "" : "?#{env[Rack::QUERY_STRING]}",
      request_id: req_id,
      trace_id: env["HTTP_TRACE_ID"],
    }
    h.merge!(self.request_tags(env))
    return h
  end

  def request_tags(_env)
    return {}
  end

  protected def log_finished(tags, began_at, status, header, exc=nil)
    elapsed = (Time.now - began_at).to_f
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
  def self.set_request_tags(**tags)
    Thread.current[:appydays_request_logger_request_tags] ||= {}
    Thread.current[:appydays_request_logger_request_tags].merge!(tags)
  end

  def self.request_tags = Thread.current[:appydays_request_logger_request_tags] || {}
end
