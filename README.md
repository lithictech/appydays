# Appydays

Rockin' all week for you.

Appydays provides logging and configuration DSLs.
It is built on top of [Semantic Logger](https://logger.rocketjob.io/)
and [dotenv](https://github.com/bkeepers/dotenv).
It is inspired to some degree by [Configurability](https://github.com/ged/configurability)
and [Loggability](https://github.com/ged/loggability) but does a lot less.

Each of logging (`appydays/loggable`), configuration (`appydays/configurable`),
and config loading (the very small `appydays/dotenviable`) can be used on their own or together.

## App Startup

Load your config through `appydays/dotenviable` if you want:

```rb
require "appydays/dotenviable"
Appydays::Dotenviable.load
```

It is a slim wrapper of `dotenv` that loads `.env.#{rack_env}.local`, `.env.#{rack_env}`, and then `.env`.

## Configurable Examples

The simplest and most common use case for `configurable` is to declare the 'namespace',
key, and default value. The namespace and key provide a default environment variable.

```rb
require 'appydays/configurable'

class MyClass
  include Appydays::Configurable
  configurable(:myclass) do
    setting :strval, "my default string"
    setting :intval, 0
    setting :boolval, true
  end
end

MyClass.strval # => 'my default string'
MyClass.intval # => 0
MyClass.boolval # => true

ENV['MYCLASS_STRVAL'] = 'newval'
ENV['MYCLASS_INTVAL'] = '1'
ENV['MYCLASS_BOOLVAL'] = 'false'

MyClass.configure
MyClass.strval # => 'newval'
MyClass.intval # => 1
MyClass.boolval # => false
```

The most common variants from this are:

### Using a different env key

```rb
class BaseModel
  include Appydays::Configurable
  configurable(:db) do
    setting :url, "postgres://localhost:5432/postgres", key: 'DATABASE_URL'
  end
end
ENV['DATABASE_URL'] = 'postgres://localhost:5432/test'
BaseModel.configure
BaseModel.url # => 'postgres://localhost:5432/test'
```

### Parsing ENV to arbitrary types

```rb
class MyClass
  include Appydays::Configurable
  configurable(:app) do
    setting :some_hash, {"x" => "default value"}, convert: ->(s) { JSON.parse(s) }
  end
end
ENV['APP_SOME_HASH'] = '{"x": "otherval"}'
MyClass.configure
MyClass.some_hash # => {'x' => 'otherval'}
```

### Side Effects

If your side effects are based on a single field, use `side_effect`:

```rb
setting :log_level_override,
    nil,
    key: "LOG_LEVEL",
    side_effect: ->(v) { Appydays::Loggable.default_level = v if v }
```

If your side effects require multiple fields, like creating an API client or configuring another library,
use `after_configured`:

```rb
module App::Sentry
  include Appydays::Configurable
  include Appydays::Loggable
  configurable(:sentry) do
    setting :dsn, ""
    after_configured do
      if self.dsn
        Raven.configure do |raven_config|
          raven_config.dsn = dsn
          raven_config.logger = self.logger
        end
      end
    end
  end
end
```

## Loggable Examples

Loggable is much simpler; it just adds a `logger` class and instance method to your model.
See Semantic Logger for info about how to use its loggers.

```rb
require 'appydays/loggable'
class MyClass
  include Appydays::Loggable
end
MyClass.logger.debug "something_happened", field: "x"
MyClass.new.logger.debug "something_happened", field: "x"
```

The biggest deal for Loggable are the additional helpers.

### Capturing Logs in Specs

```rb
logger1 = MyClass.logger

lines = capture_logs_from(logger1, formatter: :json) do
  SemanticLogger.tagged("tag1", "tag2") do
    SemanticLogger.named_tagged(nt1: 1, nt2: 2) do
      logger1.error("hello", opt1: 1, opt2: 2)
    end
  end
end
j = Yajl::Parser.parse(lines[0])
expect(j).to include("context")
expect(j["context"]).to eq(
  "_tags" => ["tag1", "tag2"],
  "nt1" => 1,
  "nt2" => 2,
  "opt1" => 1,
  "opt2" => 2,
)
```

### Patching Sequel to use Structured Logs

We love [Sequel](https://github.com/jeremyevans/sequel) and can set your DB logs up as structured logs.

```rb
require "appydays/loggable/sequel_logger"
```

Note that, by default, very long log messages (> 2000 characters) are truncated,
and the untruncated message is logged at debug.

You can control this behavior, including the size cutoff, truncation message,
context, and loging of the untruncated message. Refer to `Sequel::Database::AppydaysLogger`
for information.

### Request Loggers

Structured request logging!

```rb
require 'appydays/loggable/request_logger'
app = Rack::Builder.new do |builder|
    builder.use Appydays::Loggable::RequestLogger
    builder.run MyRackApp.new
end
```

You can use your own custom tags:

```rb
class RequestLogger < Appydays::Loggable::RequestLogger
  def request_tags(env)
    tags = super
    tags[:customer_id] = env["warden"].user(:customer)&.id || 0
    return tags
  end
end
app = Rack::Builder.new do |builder|
  builder.use RequestLogger
  builder.run MyRackApp.new
end
```

### Sidekiq

```rb
require 'appydays/loggable/sidekiq_job_logger'
Sidekiq.logger = Appydays::Loggable::SidekiqJobLogger.logger
Sidekiq.configure_server do |config|
  config.options[:job_logger] = Appydays::Loggable::SidekiqJobLogger::JobLogger
  # We do NOT want the unstructured default error handler
  config.error_handlers.replace([Appydays::Loggable::SidekiqJobLogger::JobLogger.method(:error_handler)])
  config.death_handlers << Appydays::Loggable::SidekiqJobLogger::JobLogger.method(:death_handler)
end
```

You should override it if you want to customize when jobs are logged for slowness
(default 5s):

```rb
class AppJobLogger < Appydays::Loggable::SidekiqJobLogger
  include Appydays::Configurable
  configurable(:job_logger) do
    setting :slow_job_seconds, 1.0
  end
  
  protected def slow_job_seconds
    return self.class.slow_job_seconds
  end
end

Sidekiq.logger = AppJobLogger.logger
Sidekiq.configure_server do |config|
  config.options[:job_logger] = AppJobLogger::JobLogger
  # We do NOT want the unstructured default error handler
  config.error_handlers.replace([AppJobLogger::JobLogger.method(:error_handler)])
  config.death_handlers << AppJobLogger::JobLogger.method(:death_handler)
end
```

For most jobs, you'll want to set log tags. Use `with_log_tags` to set tags for a block.

```rb
class MyJob
  def perform
    Appydays::Loggable::SidekiqJobLogger.with_log_tags(some_tag: 'some value') do
      MyApp.do_thing
    end
  end
end
# Log messages from MyApp#do_thing include the tag {some_tag: 'some value'}
```

You can also set fields that are logged in the `job_done` (or `job_fail`) message
that is output when the job is finished.
This is useful when you want to log the output of the job,
but not redundantly. Ie, `logger.info "finished_doing_thing", user_id: user.id` along
with a `"job_done"` message after that (missing `user_id`) is redundant.
Instead, use `set_job_tags` within the job, so the `"job_done"` message includes them:

```rb
# WRONG, will result in two messages, "job_done" will not have 'done_count' field
class MyJob
  def perform
    count = MyApp.do_thing
    self.logger.info "finished_my_thing", done_count: count 
  end
end

# RIGHT, will result in one "job_done" message, which will include the 'done_count' field
class MyJob
  def perform
    count = MyApp.do_thing
    Appydays::Loggable::SidekiqJobLogger.set_job_tags(done_count: count)
  end
end
```

### HTTParty

Well structured logs for HTTParty!

```rb
require 'appydays/loggable/httparty_formatter'
logger = SemanticLogger["my_app_logger"]
HTTParty.post("https://foo/bar", body: {x: 1}, logger: logger, log_format: :appydays)
```


### Sentry

If Sentry is available, all calls to `with_named_tags` (which configure `SemanticLogger` tags)
will also set the `extras` on the current Sentry scope. If Sentry is not loaded, or is not active,
this will noop.
