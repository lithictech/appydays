# frozen_string_literal: true

require_relative "lib/appydays/version"

Gem::Specification.new do |s|
  s.name = "appydays"
  s.version = Appydays::VERSION
  s.platform = Gem::Platform::RUBY
  s.summary = "Provides support for env-based configuration, and common structured logging capabilities"
  s.author = "Lithic Tech"
  s.homepage = "https://github.com/lithictech/appydays"
  s.licenses = "MIT"
  s.required_ruby_version = ">= 2.7.0"
  s.description = <<~DESC
    appydays provides support for env-based configuration, and common structured logging capabilities
  DESC
  s.files = Dir["lib/**/*.rb"]
  s.add_dependency("dotenv", "~> 2.7")
  s.add_dependency("semantic_logger", "~> 4.6")
  s.add_development_dependency("rack", "~> 2.2")
  s.add_development_dependency("rspec", "~> 3.10")
  s.add_development_dependency("rspec-core", "~> 3.10")
  s.add_development_dependency("rspec-json_expectations", "~> 2.2")
  s.add_development_dependency("rubocop", "~> 1.11")
  s.add_development_dependency("rubocop-performance", "~> 1.10")
  s.add_development_dependency("rubocop-rake", "~> 0.5")
  s.add_development_dependency("rubocop-sequel", "~> 0.2")
  s.add_development_dependency("sequel", "~> 5.0")
  s.add_development_dependency("sidekiq", "~> 6.0")
end
