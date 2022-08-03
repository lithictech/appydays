# frozen_string_literal: true

require "appydays/spec_helpers"

RSpec.describe Appydays::SpecHelpers do
  describe "have_a_line_matching" do
    it "matches lines" do
      lines = "abc\ndef\nghi"
      expect(lines).to have_a_line_matching(/def/)
      expect(lines.lines).to have_a_line_matching(/def/)
      expect(lines).to_not have_a_line_matching(/xyz/)
      expect(lines.lines).to_not have_a_line_matching(/xyz/)
    end
    it "is composable" do
      expect({x: "a\nb"}).to include(x: have_a_line_matching(/a/))
    end
  end

  describe "have_length" do
    it "matches length" do
      expect([]).to have_length(0)
      expect([1]).to have_length(1)
      expect([1, 1]).to have_length(2)
      expect([]).to_not have_length(2)
      expect([1, 2, 3]).to_not have_length(2)
    end
    it "is composable" do
      expect({x: "ab"}).to include(x: have_length(2))
    end
  end

  describe "cost" do
    before(:all) do
      require "money"
      require "monetize"
      Money.rounding_mode = BigDecimal::ROUND_HALF_UP
    end
    before(:each) do
      Money.default_currency = nil
      Monetize.assume_from_symbol = false
    end
    it "compares cost" do
      m = Money.new(100, "USD")
      expect(m).to cost("$1")
      expect(m).to cost("$1.00")
      expect(m).to_not cost("$1.01")
      expect(m).to cost(Money.new(100, "USD"))
      expect(m).to_not cost(Money.new(101, "USD"))
      expect(m).to cost(100, "USD")
      expect(m).to_not cost(101, "USD")
    end
    it "can work with default currency" do
      m = Money.new(100, "USD")
      Money.default_currency = "USD"
      expect(m).to cost("1")
      expect(m).to cost("1.00")
      expect(m).to_not cost("1.01")
      expect(m).to cost(100)
      expect(m).to_not cost(101)
    end
    it "errors if no currency can be found" do
      m = Money.new(100, "USD")
      expect { expect(m).to cost(100) }.to raise_error(Money::Currency::UnknownCurrency)
      expect { expect(m).to cost("1") }.to raise_error(Money::Currency::UnknownCurrency, /Could not parse/)
    end
    it "is composable" do
      expect({x: Money.new(500, "USD")}).to include(x: cost("$5"))
    end
  end

  describe "match_time" do
    t = Time.parse("2025-10-01T5:10:20.456789-07:00")
    it "matches time" do
      expect(t).to match_time(t)
      expect(t).to match_time(t + 0.0001)
      expect(t).to_not match_time(t + 1)
      expect(t).to match_time(t + 2).within(5)
      expect(t).to match_time(t.to_f)
      expect(t).to match_time(t.to_i).within(1)

      expect(t).to match_time("2025-10-01T5:10:20.456789-07:00")
      expect(t).to match_time("2025-10-01T4:10:20.456789-08:00")
    end
    it "matches now" do
      expect(Time.now + 2).to match_time(:now)
      expect(Time.now).to match_time(:now)
      expect(Time.now - 6).to_not match_time(:now)
    end
    it "is composable" do
      expect({x: Time.now}).to include(x: match_time(:now))
      expect({x: t}).to include(x: match_time(t.to_f))
    end
  end
end
