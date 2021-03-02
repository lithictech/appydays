# frozen_string_literal: true

source "https://rubygems.org"
ruby "2.7.2"

gem "dotenv"
gem "httparty"
gem "semantic_logger"

# By default, Heroku ignores 'test' gem groups.
# But for ci, we need these gems loaded. It doesn't appear possible to 'fool' heroku using BUNDLE_WITHOUT
# to only exclude some fake group.
# So we include this test group by default, then BUNDLE_WITHOUT the real apps.
group :test_group do
  gem "rack-test"
  gem "rspec"
  gem "rspec-json_expectations"
  gem "rubocop"
  gem "rubocop-performance", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-sequel", require: false
  gem "timecop"
  gem "webmock"
end
