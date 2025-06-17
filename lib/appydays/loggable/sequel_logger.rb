# frozen_string_literal: true

# Patch Sequel::Database logging methods for structured logging
require "sequel/database/logging"

class Sequel::Database
  # Helpers for the Appydays Sequel logger.
  # Very long messages may end up getting logged; the logger will truncate anything
  # longer than +truncate_messages_over+, with +truncation_context+ number of chars
  # at the beginning and at the end.
  #
  # If a message is truncated, the full message is logged at +log_full_message_level+ (default :debug).
  # Use nil to disable the full message logging.
  module AppydaysLogger
    class << self
      # Messages more than this many characters are truncated.
      # Defaults to 2000.
      attr_accessor :truncate_messages_over

      # Placeholder message when truncation occurs.
      # Defaults to '<truncated>'.
      attr_accessor :truncation_message

      # How many characters to preserve before and after truncation.
      # Defaults to 200 (400 total).
      attr_accessor :truncation_context

      # If set, log the full message at this level when truncation occurs.
      # For example, a truncated message may be logged at :info,
      # and the full message logged at +:default+.
      # Defaults to +nil+ (does not log full messages when truncation occurs).
      attr_accessor :log_full_message_level

      # Log slow queries at this level.
      # See +Sequel::Database#log_warn_duration+.
      # Default to +:warn+.
      attr_accessor :slow_query_log_level

      def setdefaults
        @truncate_messages_over = 2000
        @truncation_message = "<truncated>"
        @truncation_context = 200
        @slow_query_log_level = :warn
      end

      def truncate_message(message)
        return message if message.size <= self.truncate_messages_over
        msg = message[...self.truncation_context] + self.truncation_message + message[-self.truncation_context..]
        return msg
      end
    end
  end
  AppydaysLogger.setdefaults

  def log_exception(exception, message)
    level = message.match?(/^SELECT NULL AS "?nil"? FROM .* LIMIT 1$/i) ? :debug : :error
    log_each(
      level,
      proc { "#{exception.class}: #{exception.message.strip if exception.message}: #{message}" },
      proc { ["sequel_exception", {sequel_message: message}, exception] },
    )
  end

  # Log a message at level info to all loggers.
  def log_info(message, args=nil)
    log_each(
      :info,
      proc { args ? "#{message}; #{args.inspect}" : message },
      proc do
        o = {message:}
        o[:args] = args unless args.nil?
        ["sequel_log", o]
      end,
    )
  end

  # Log message with message prefixed by duration at info level, or
  # warn level if duration is greater than log_warn_duration.
  def log_duration(duration, message)
    lwd = log_warn_duration
    was_truncated = false
    log_each(
      lwd && (duration >= lwd) ? AppydaysLogger.slow_query_log_level : sql_log_level,
      proc { "(#{'%0.6fs' % duration}) #{message}" },
      proc do
        query = AppydaysLogger.truncate_message(message)
        params = {duration: duration * 1000, query:}
        if query != message
          params[:truncated] = true
          was_truncated = true
        end
        ["sequel_query", params]
      end,
    )
    return unless was_truncated && Sequel::Database::AppydaysLogger.log_full_message_level
    log_each(
      Sequel::Database::AppydaysLogger.log_full_message_level,
      nil,
      proc { ["sequel_query_debug", {duration: duration * 1000, query: message}] },
    )
  end

  def log_each(level, std, semantic)
    @loggers.each do |logger|
      if logger.is_a?(SemanticLogger::Base)
        logger.public_send(level, *semantic.call)
      elsif std
        logger.public_send(level, std.call)
      end
    end
  end
end
