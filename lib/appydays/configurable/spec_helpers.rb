# frozen_string_literal: true

require "appydays/configurable"

module Appydays::Configurable::SpecHelpers
  def self.included(context)
    context.around(:each) do |example|
      to_reset = example.metadata[:reset_configuration]
      if to_reset
        to_reset = [to_reset] unless to_reset.respond_to?(:to_ary)
        to_reset.each(&:reset_configuration)
      end
      begin
        example.run
      ensure
        to_reset&.each(&:reset_configuration)
      end
    end
  end
end
