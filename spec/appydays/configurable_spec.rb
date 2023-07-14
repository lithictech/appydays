# frozen_string_literal: true

require "appydays/configurable/spec_helpers"

RSpec.describe Appydays::Configurable do
  before(:each) do
    @orig_keys = ENV.keys
  end
  after(:each) do
    ENV.delete_if { |k| !@orig_keys.include?(k) }
  end
  describe "configurable" do
    it "raises if no block is given" do
      expect do
        Class.new do
          include Appydays::Configurable
          configurable(:hello)
        end
      end.to raise_error(LocalJumpError)
    end

    describe "setting" do
      it "creates an attr accessor with the given name and default value" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "zero"
          end
        end
        expect(cls).to have_attributes(knob: "zero")
      end

      it "pulls the value from the environment" do
        ENV["ENVTEST_KNOB"] = "one"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:envtest) do
            setting :knob, "zero"
          end
        end
        expect(cls).to have_attributes(knob: "one")
      end

      it "can use a custom environment key" do
        ENV["OTHER_KNOB"] = "two"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "zero", key: "OTHER_KNOB"
          end
        end
        expect(cls).to have_attributes(knob: "two")
      end

      it "can use an array of environment keys" do
        ENV["KNOB2"] = "two"
        ENV["KNOB3"] = "three"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "zero", key: ["KNOB1", "KNOB2", "KNOB3"]
          end
        end
        expect(cls).to have_attributes(knob: "two")
      end

      it "can use a default if no env keys are found" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "zero", key: ["KNOB1", "KNOB2"]
          end
        end
        expect(cls).to have_attributes(knob: "zero")
      end

      it "can convert the value given the converter" do
        ENV["CONVTEST_KNOB"] = "0"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:convtest) do
            setting :knob, "", convert: ->(v) { v + v }
          end
        end
        expect(cls).to have_attributes(knob: "00")
      end

      it "does not run the converter if the default is used" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "0", convert: ->(v) { v + v }
          end
        end
        expect(cls).to have_attributes(knob: "0")
      end

      it "can use a nil default" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, nil
          end
        end
        expect(cls).to have_attributes(knob: nil)
      end

      it "converts strings to floats if the default is a float" do
        ENV["FLOATTEST_KNOB"] = "3.2"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:floattest) do
            setting :knob, 1.5
          end
        end
        expect(cls).to have_attributes(knob: 3.2)
      end

      it "converts strings to integers if the default is an integer" do
        ENV["INTTEST_KNOB"] = "5"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:inttest) do
            setting :knob, 2
          end
        end
        expect(cls).to have_attributes(knob: 5)
      end

      it "can coerce strings to booleans" do
        ENV["BOOLTEST_KNOB"] = "TRue"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:booltest) do
            setting :knob, false
          end
        end
        expect(cls).to have_attributes(knob: true)
      end

      it "can coerce strings to symbols" do
        ENV["SYMTEST_KNOB"] = "spam"
        cls = Class.new do
          include Appydays::Configurable
          configurable(:symtest) do
            setting :knob, :ham
          end
        end
        expect(cls).to have_attributes(knob: :spam)
      end

      it "does not run the converter when using the accessor" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:booltest) do
            setting :knob, 5
          end
        end
        cls.knob = "5"
        expect(cls).to have_attributes(knob: "5")
      end

      it "coalesces an empty string to nil" do
        cls = Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, ""
          end
        end
        expect(cls).to have_attributes(knob: nil)
      end

      it "errors if the default value is not a supported type" do
        expect do
          Class.new do
            include Appydays::Configurable
            configurable(:hello) do
              setting :knob, []
            end
          end
        end.to raise_error(TypeError)
      end

      it "runs a side effect" do
        side_effect = []
        Class.new do
          include Appydays::Configurable
          configurable(:hello) do
            setting :knob, "zero", side_effect: ->(s) { side_effect << s }
          end
        end
        expect(side_effect).to contain_exactly("zero")
      end
    end

    it "can reset settings" do
      cls = Class.new do
        include Appydays::Configurable
        configurable(:hello) do
          setting :knob, 1
        end
      end
      cls.knob = 5
      expect(cls).to have_attributes(knob: 5)
      cls.reset_configuration
      expect(cls).to have_attributes(knob: 1)
    end

    it "runs after_configure hooks after configuration" do
      side_effect = []
      Class.new do
        include Appydays::Configurable
        configurable(:hello) do
          setting :knob, 1
          after_configured do
            side_effect << self.knob
          end
        end
      end
      expect(side_effect).to contain_exactly(1)
    end

    it "can reset settings using the given parameters as new config values" do
      side_effect = []
      cls = Class.new do
        include Appydays::Configurable
        configurable(:hello) do
          setting :knob, 1
          after_configured do
            side_effect << self.knob
          end
        end
      end
      expect(side_effect).to contain_exactly(1)
      cls.reset_configuration(knob: 12, widget: 5)
      expect(side_effect).to contain_exactly(1, 12)
      expect(cls.knob).to eq(12)
    end

    it "can run after_configured hooks explicitly" do
      side_effect = []
      cls = Class.new do
        include Appydays::Configurable
        configurable(:hello) do
          setting :knob, 1
          after_configured do
            side_effect << self.knob
          end
        end
      end
      cls.run_after_configured_hooks
      expect(side_effect).to contain_exactly(1, 1)
    end
  end

  describe "spec helpers" do
    describe "reset_configuration metadata" do
      c1 = Class.new do
        include Appydays::Configurable
        configurable(:c1) do
          setting :x, 1
        end
      end
      c2 = Class.new do
        include Appydays::Configurable
        configurable(:c2) do
          setting :x, 2
        end
      end
      around(:each) do |ex|
        c1.x = 5
        c2.x = 6
        ex.run
        expect(c1.x).to eq(1)
      end
      describe "resets configuration of" do
        include Appydays::Configurable::SpecHelpers
        it "a passed class", reset_configuration: c1 do
          expect(c1.x).to eq(1)
          expect(c2.x).to eq(6)
          c1.x = 5
          c2.x = 6
        end
        it "passed classes", reset_configuration: [c1, c2] do
          expect(c1.x).to eq(1)
          expect(c2.x).to eq(2)
          c1.x = 5
          c2.x = 6
        end
      end
    end
  end
end
