# frozen_string_literal: true

require_relative "lib/appydays/version"

Gem::Specification.new do |s|
  s.name = "appydays"
  s.version = Appydays::VERSION
  s.platform = Gem::Platform::RUBY
  s.summary = "Provides support for env-based configuration, and common structured logging capabilities"
  s.author = "Lithic Tech"
  s.required_ruby_version = ">= 2.7.0"
  s.description = <<~DESC
    appydays provides support for env-based configuration, and common structured logging capabilities
  DESC
  s.add_dependency("dotenv")
  s.add_dependency("semantic_logger")
  s.add_development_dependency("rack")
  s.add_development_dependency("rspec")
  s.add_development_dependency("rspec-core")
  s.add_development_dependency("rspec-json_expectations")
  s.add_development_dependency("rubocop")
  s.add_development_dependency("rubocop-performance")
  s.add_development_dependency("rubocop-rake")
  s.add_development_dependency("rubocop-sequel")
  s.add_development_dependency("sequel")
end
