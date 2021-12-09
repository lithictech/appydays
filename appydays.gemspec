# frozen_string_literal: true

# rubocop:disable Lint/UselessAssignment
spec = Gem::Specification.new do |s|
  s.name = "appydays"
  s.version = "0.1.0"
  s.platform = Gem::Platform::RUBY
  s.summary = "Provides support for development best practices"
  s.author = "Lithic Tech"
  s.required_ruby_version = ">= 2.7.0"
  s.description = <<~DESC
    appydays provides support for logging and handling environment variables
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
# rubocop:enable Lint/UselessAssignment
