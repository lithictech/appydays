# frozen_string_literal: true

require "httparty"

# Formatter that sends structred log information to HTTParty.
# After requiring this module, use
# `HTTParty.<method>(..., logger: semantic_logger, log_format: :appydays)`
# to write out a nice structured log.
# You can also subclass this formatter to use your own message (default to httparty_request),
# and modify the fields (override #fields).
class Appydays::Loggable::HTTPartyFormatter
  attr_accessor :level, :logger, :message
  attr_reader :request, :response

  def initialize(logger, level)
    @logger = logger
    @level  = level.to_sym
    @message = "httparty_request"
  end

  def format(request, response)
    @request = request
    @response = response
    self.logger.public_send(self.level, self.message, **self.fields)
  end

  def fields
    return {
      "content_length" => content_length || "-",
      "http_method" => http_method,
      "path" => path,
      "response_code" => response.code,
    }
  end

  def http_method
    @http_method ||= request.http_method.name.split("::").last.upcase
  end

  def path
    @path ||= request.path.to_s
  end

  def content_length
    @content_length ||= response.respond_to?(:headers) ? response.headers["Content-Length"] : response["Content-Length"]
  end
end

HTTParty::Logger.add_formatter(:appydays, Appydays::Loggable::HTTPartyFormatter)
