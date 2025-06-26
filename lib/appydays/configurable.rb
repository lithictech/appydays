# frozen_string_literal: true

require "appydays/version"

##
# Define the configuration for a module or class.
#
# Usage:
#     include Appydays::Configurable
#     configurable(:myapp) do
#       setting :log_level, 'debug', env: 'LOG_LEVEL'
#       setting :app_url, 'http://localhost:3000'
#       setting :workers, 4
#     end
#
# The module or class that extends Configurable will get two singleton methods,
# `log_level` and `app_url`.
# The first will be be given a value of `ENV.fetch('LOG_LEVEL', 'debug')`,
# because the env key is provided.
#
# The second will be given a value of `ENV.fetch('MYAPP_APP_URL', 'http:://localhost:3000')`,
# because the env key is defaulted.
#
# The second will be given a value of `4.class(ENV.fetch('MYAPP_WORKERS', 4))`.
# Note it will coerce the type of the env value to the type of the default.
# Empty strings will be coerced to nil.
#
# The `setting` method has several other options;
# see its documentation for more details.
#
# The target will also get a `reset_configuration` method that will restore defaults,
# and `run_after_configured_hooks`. See their docs for more details.
#
module Appydays::Configurable
  def self.included(target)
    target.extend(ClassMethods)
  end

  module ClassMethods
    def configurable(key, &block)
      raise LocalJumpError unless block

      installer = Installer.new(self, key)

      self.define_singleton_method(:_configuration_installer) { installer }

      installer.instance_eval(&block)
      installer._run_after_configured
    end

    ##
    # Restore all settings back to the values they were at config time
    # (undoes any manual attribute writes), and runs after_configured hooks.
    #
    # overrides can be passed, to apply new manual overrides
    # before running after_configured hooks.
    # This is very useful when testing classes that have an after_configured hook.
    def reset_configuration(overrides={})
      self._configuration_installer._reset(overrides)
    end

    ##
    # Explicitly run after configuration hooks.
    # This may need to be run explicitly after reset,
    # if the `after_configured` hook involves side effects.
    # Side effects are gnarly so we don't make assumptions.
    def run_after_configured_hooks
      self._configuration_installer._run_after_configured
    end
  end

  class Installer
    def initialize(target, group_key)
      @target = target
      @group_key = group_key
      @settings = {}
      @after_config_hooks = []
    end

    ##
    # Define a setting for the receiver,
    # which acts as an attribute accessor.
    #
    # Params:
    #
    # name: The name of the accessor/setting.
    # default: The default value.
    #   If `convert` is not supplied, this must be nil, or a string, int, float, or boolean,
    #   so the parsed environment value can be converted/coerced into the same type as 'default'.
    #   If convert is passed, that is used as the converter so the default value can be any type.
    # key: The key to lookup the config value from the environment.
    #   If nil, use an auto-generated combo of the configuration key and method name.
    #   If key is an array, look up each (string) value as a key.
    #   The first non-nil (ie, `ENV.fetch(x, nil)`) value will be used.
    # convert: If provided, call it with the string value so it can be parsed.
    #   For example, you can parse a string JSON value here.
    #   Convert will not be called with the default value.
    # side_effect: If this setting should have a side effect,
    #   like configuring an external system, it should happen in this proc/lambda.
    #   It is called with the parsed/processed config value.
    #
    # Note that only ONE conversion will happen, and
    # - If converter is provided, it will be used with the environment value.
    def setting(name, default, key: nil, convert: nil, side_effect: nil)
      installer = self

      @target.define_singleton_method(name) do
        self.class_variable_get("@@#{name}")
      end
      @target.define_singleton_method(:"#{name}=") do |v|
        installer._set_value(name, v, side_effect)
      end

      key ||= "#{@group_key}_#{name}".upcase
      keys = Array(key)
      env_value = keys.filter_map { |k| ENV.fetch(k, nil) }.first
      converter = self._converter(default, convert)
      value = env_value.nil? ? default : converter[env_value]
      value = installer._set_value(name, value, side_effect)
      @settings[name] = value
    end

    def _set_value(name, value, side_effect)
      value = nil if value == ""
      # rubocop:disable Style/ClassVars
      self._target.class_variable_set("@@#{name}", value)
      # rubocop:enable Style/ClassVars
      self._target.instance_exec(value, &side_effect) if side_effect
      return value
    end

    def after_configured(&block)
      @after_config_hooks << block
    end

    def _converter(default, converter)
      return converter if converter

      return lambda(&:to_s) if default.nil? || default.is_a?(String)
      return lambda(&:to_i) if default.is_a?(Integer)
      return lambda(&:to_f) if default.is_a?(Float)
      return lambda(&:to_sym) if default.is_a?(Symbol)
      return ->(v) { v.casecmp("true").zero? } if [TrueClass, FalseClass].include?(default.class)
      raise TypeError, "Uncoercable type %p" % [default.class]
    end

    def _target
      return @target
    end

    def _group_key
      return @group_key
    end

    def _run_after_configured
      @after_config_hooks.each do |h|
        @target.instance_eval(&h)
      end
    end

    def _reset(overrides)
      @settings.each do |k, v|
        real_v = overrides.fetch(k, v)
        @target.send(:"#{k}=", real_v)
      end
      self._run_after_configured
    end
  end
end
