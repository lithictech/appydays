# frozen_string_literal: true

require "appydays/version"

RSpec::Matchers.define_negated_matcher(:exclude, :include)
RSpec::Matchers.define_negated_matcher(:not_include, :include)
RSpec::Matchers.define_negated_matcher(:not_change, :change)
RSpec::Matchers.define_negated_matcher(:not_be_nil, :be_nil)
RSpec::Matchers.define_negated_matcher(:not_be_empty, :be_empty)

module Appydays::SpecHelpers
  # Zero out nsecs to t can be compared to one from the database.
  module_function def trunc_time(t)
    return t.change(nsec: t.usec * 1000)
  end

  #
  # :section: Matchers
  #

  class HaveALineMatching
    def initialize(regexp)
      @regexp = regexp
    end

    def matches?(target)
      @target = target
      @target = @target.lines if @target.is_a?(String)
      return @target.find do |obj|
        obj.to_s.match(@regexp)
      end
    end

    def failure_message
      return "expected %p to have at least one line matching %p" % [@target, @regexp]
    end

    alias failure_message_for_should failure_message

    def failure_message_when_negated
      return "expected %p not to have any lines matching %p, but it has at least one" % [@target, @regexp]
    end

    alias failure_message_for_should_not failure_message_when_negated
  end

  # RSpec matcher -- set up the expectation that the lefthand side
  # is Enumerable, and that at least one of the objects yielded
  # while iterating matches +regexp+ when converted to a String.
  module_function def have_a_line_matching(regexp)
    return HaveALineMatching.new(regexp)
  end

  module_function def have_length(x)
    return RSpec::Matchers::BuiltIn::HaveAttributes.new(length: x)
  end

  class MatchTime
    def initialize(expected)
      @expected = expected
      if expected == :now
        @expected_t = Time.now
        @tolerance = 5
      else
        @expected_t = self.time(expected)
        @tolerance = 0.001
      end
    end

    def time(s)
      return nil if s.nil?
      return Time.parse(s) if s.is_a?(String)
      return s.to_time
    end

    def matches?(actual)
      @actual_t = self.time(actual)
      @actual_t = self.change_tz(@actual_t, @expected_t.zone) if @actual_t
      return RSpec::Matchers::BuiltIn::BeWithin.new(@tolerance).of(@expected_t).matches?(@actual_t)
    end

    protected def change_tz(t, zone)
      return t.change(zone: zone) if t.respond_to?(:change)
      prev_tz = ENV.fetch("TZ", nil)
      begin
        ENV["TZ"] = zone
        return Time.at(t.to_f)
      ensure
        ENV["TZ"] = prev_tz
      end
    end

    def within(tolerance)
      @tolerance = tolerance
      return self
    end

    def failure_message
      return "expected %s to be within %s of %s" % [@actual_t, @tolerance, @expected_t]
    end
  end

  # Matcher that will compare a string or time expected against a string or time actual,
  # within a tolerance (default to 1 millisecond).
  #
  # Use match_time(:now) to automatically `match_time(Time.now).within(5.seconds)`.
  #
  #   expect(last_response).to have_json_body.that_includes(
  #       closes_at: match_time('2025-12-01T00:00:00.000+00:00').within(1.second))
  #
  def match_time(expected)
    return MatchTime.new(expected)
  end

  # Matcher that will compare a string or Money expected against a string or Money actual.
  #
  #   expect(order.total).to cost('$25')
  #
  RSpec::Matchers.define(:cost) do |expected, currency|
    match do |actual|
      @base = RSpec::Matchers::BuiltIn::Eq.new(self.money(expected, currency))
      @base.matches?(self.money(actual))
    end

    failure_message do |_actual|
      @base.failure_message
    end

    def money(s, currency=nil)
      if (m = self.tryparse(s, currency))
        return m
      end
      return s if s.is_a?(Money)
      return Money.new(s, currency) if s.is_a?(Integer)
      return Money.new(s[:cents], s[:currency]) if s.respond_to?(:key?) && s.key?(:cents) && s.key?(:currency)
      raise "#{s} type #{s.class.name} not convertable to Money (add support or use supported type)"
    end

    def tryparse(s, currency)
      # We need to capture some global settings while we parse, and set them back after.
      orig_default = Money.instance_variable_get(:@default_currency)
      orig_assume = Monetize.assume_from_symbol
      return nil unless s.is_a?(String)
      # See https://github.com/RubyMoney/monetize/issues/161
      # To get around this, need to use a valid custom currency
      begin
        Money::Currency.new("APPYDAYS")
      rescue Money::Currency::UnknownCurrency
        Money::Currency.register(iso_code: "APPYDAYS", subunit_to_unit: 1)
      end
      Money.default_currency = currency || orig_default || "APPYDAYS"
      Monetize.assume_from_symbol = true
      m = Monetize.parse!(s)
      return m unless m.currency == "APPYDAYS"
      raise Money::Currency::UnknownCurrency,
            "Could not parse currency from '#{s}'. It needs a symbol, or set default_currency."
    ensure
      Money.default_currency = orig_default
      Monetize.assume_from_symbol = orig_assume
    end
  end
end
