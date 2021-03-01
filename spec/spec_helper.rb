# frozen_string_literal: true

# See https://github.com/eliotsykes/rspec-rails-examples/blob/master/spec/spec_helper.rb
# See http://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
#
require "appydays/dotenviable"
Appydays::Dotenviable.load(default_rack_env: "test")

require "httparty"
require "rack/test"
require "rack/test/methods"
require "rspec"
require "rspec/json_expectations"
require "timecop"
require "webmock/rspec"
require "appydays/loggable/spec_helpers"
require "appydays/configurable"


RSpec.configure do |config|
  # config.full_backtrace = true

  RSpec::Support::ObjectFormatter.default_instance.max_formatted_output_length = 600

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  Kernel.srand config.seed

  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?

  config.include(Appydays::Loggable::SpecHelpers)
end
