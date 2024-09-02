# frozen_string_literal: true

RSpec.describe Appydays::Dotenviable do
  it "loads env files using RACK_ENV" do
    expect(Dotenv).to receive(:load).with(".env.foo.local", ".env.foo", ".env")
    described_class.load(env: {"RACK_ENV" => "foo"})
  end

  it "loads env files using the explicit env" do
    expect(Dotenv).to receive(:load).with(".env.bar.local", ".env.bar", ".env")
    described_class.load(rack_env: "bar")
  end

  it "loads env files with the given default env if no RACK_ENV is defined" do
    expect(Dotenv).to receive(:load).with(".env.bar.local", ".env.bar", ".env")
    described_class.load(default_rack_env: "bar", env: {})
  end

  it "loads env files with RACK_ENV rather than the default, if RACK_ENV is defined" do
    expect(Dotenv).to receive(:load).with(".env.bar.local", ".env.bar", ".env")
    described_class.load(default_rack_env: "foo", env: {"RACK_ENV" => "bar"})
  end

  it "reapplies the original port if one was not loaded" do
    env = {"PORT" => "123"}
    expect(Dotenv).to receive(:load)
    described_class.load(env:)
    expect(env).to include("PORT" => "123")
  end

  it "defaults RACK_ENV to what was used for loading" do
    env = {"RACK_ENV" => "original"}
    expect(Dotenv).to receive(:load)
    described_class.load(env:)
    expect(env).to include("RACK_ENV" => "original")

    env = {}
    expect(Dotenv).to receive(:load)
    described_class.load(env:, default_rack_env: "xyz")
    expect(env).to include("RACK_ENV" => "xyz")
  end

  it "does not reapply the original port if one was loaded" do
    env = {"PORT" => "123"}
    expect(Dotenv).to receive(:load) { env["PORT"] = "456" }
    described_class.load(env:)
    expect(env).to include("PORT" => "456")
  end

  it "can load into a separate hash" do
    ENV["HASHTESTABC"] = "x"
    File.write(".env.hashtest", "HASHTESTXYZ=a")
    e = {}
    described_class.load(rack_env: "hashtest", env: e)
    expect(e).to include("HASHTESTXYZ" => "a")
    expect(e).to_not include("HASHTESTABC")
    expect(ENV.to_h).to_not include("HASHTESTXYZ")
    expect(ENV.to_h).to include("HASHTESTABC" => "x")
  ensure
    File.delete(".env.hashtest")
    ENV.delete("HASHTESTABC")
  end
end
