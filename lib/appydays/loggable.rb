# frozen_string_literal: true

require "semantic_logger"
require "semantic_logger/formatters/raw"
require "semantic_logger/formatters/json"

require "appydays/version"

##
# Override SemanticLogger's keys for tags, named_tags, and payload.
# It is emminently unhelpful to have three places the same data may be-
# ie, in some cases, we may have a customer_id in a named tag,
# sometimes in payload, etc. Callsite behavior should not vary
# the shape/content of the log message.
class SemanticLogger::Formatters::Raw
  alias original_call call

  def call(log, logger)
    h = self.original_call(log, logger)
    ctx = h[:context] ||= {}
    ctx[:_tags] = h.delete(:tags) if h.key?(:tags)

    [:named_tags, :payload].each do |hash_key|
      next unless h.key?(hash_key)
      h.delete(hash_key).each do |k, v|
        ctx[k] = v
      end
    end

    return h
  end
end

# SemanticLogger Formatter that truncates large strings in the structured log payload.
# If the emitted JSON log is longer than +max_message_len+:
# - the payload is walked,
# - any strings with a length greater than +max_string_len+ are shortened using +shorten_string+.
#   Override +shorten_string+ for custom behavior.
# - any key +:stack_trace+ has its array truncated. Stack traces are very large,
#   but contain short strings. Override +truncate_stack_trace+ for custom behavior.
class SemanticLogger::Formatters::JsonTrunc < SemanticLogger::Formatters::Raw
  attr_accessor :max_message_len, :max_string_len

  def initialize(max_message_len: 1024 * 3, max_string_len: 300, **args)
    super(**args)
    @max_message_len = max_message_len
    @max_string_len = max_string_len
  end

  def truncate_at(max_message_len, max_string_len)
    @max_message_len = max_message_len
    @max_string_len = max_string_len
  end

  def call(log, logger)
    r = super
    rj = r.to_json
    return rj if rj.length <= @max_message_len
    rshort = self.trim_long_strings(r)
    return rshort.to_json
  end

  def trim_long_strings(v)
    case v
      when Hash
        v.each_with_object({}) do |(hk, hv), memo|
          memo[hk] =
            if hk == :stack_trace && hv.is_a?(Array)
              self.truncate_stack_trace(hv)
            else
              self.trim_long_strings(hv)
            end
        end
      when Array
        v.map { |item| self.trim_long_strings(item) }
      when String
        if v.size > @max_string_len
          self.shorten_string(v)
        else
          v
        end
      else
        v
    end
  end

  # Given a long string, return the truncated string.
  # @param v [String]
  # @return [String]
  def shorten_string(v)
    return v[..@max_string_len] + "..."
  end

  # Given a stack trace array, return the array to log.
  # @param arr [Array]
  # @return [Array]
  def truncate_stack_trace(arr)
    return arr if arr.length <= 4
    return [arr[0], arr[1], "skipped #{arr.length - 4} frames", arr[-2], arr[-1]]
  end
end

##
# Helpers for working with structured logging.
# Use this instead of calling semantic_logger directly.
# Generally you `include Appydays::Loggable`
module Appydays::Loggable
  def self.included(target)
    target.include(SemanticLogger::Loggable)

    target.extend(Methods)
    target.include(Methods)
  end

  def self.default_level=(v)
    self.set_default_level(v)
  end

  def self.set_default_level(v, warning: true)
    return if v == SemanticLogger.default_level
    self[self].warn "Overriding log level to %p" % v if warning
    SemanticLogger.default_level = v
  end

  ##
  # Return the logger for a key/object.
  def self.[](key)
    return key.logger if key.respond_to?(:logger)
    (key = key.class) unless [Module, Class].include?(key.class)
    return SemanticLogger[key]
  end

  ##
  # Configure logging for 12 factor applications.
  # Specifically, that means setting STDOUT to synchronous,
  # using STDOUT as the log output,
  # and also conveniently using color formatting if using a tty or json otherwise
  # (ie, you want to use json logging on a server).
  def self.configure_12factor(format: nil, application: nil)
    format ||= $stdout.isatty ? :color : :json
    $stdout.sync = true
    SemanticLogger.application = application if application
    SemanticLogger.add_appender(io: $stdout, formatter: format.to_sym)
  end

  def self.with_log_tags(tags)
    if defined?(Sentry)
      Sentry.configure_scope do |scope|
        scope.set_extras(tags)
      end
    end
    blockresult = nil
    SemanticLogger.named_tagged(tags) do
      blockresult = yield
    end
    return blockresult
  end

  @stderr_appended = false

  def self.ensure_stderr_appender
    return if @stderr_appended
    SemanticLogger.add_appender(io: $stderr)
    @stderr_appended = true
  end

  module Methods
    def with_log_tags(tags, &)
      return SemanticLogger.named_tagged(tags, &)
    end
  end
end
