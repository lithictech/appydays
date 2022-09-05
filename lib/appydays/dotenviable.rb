# frozen_string_literal: true

require "dotenv"

require "appydays/version"

##
# Wrapper over dotenv that will load the standard .env files for an environment
# (by convention, .env.<env>.local, .env.<env>, and .env).
#
# It can be called multiple times for the same environment.
# There are a couple special cases for RACK_ENV and PORT variables:
#
# RACK_ENV variable: Dotenviable defaults the $RACK_ENV variable to whatever
# is used for dotfile loading (ie, the `rack_env` or `default_rack_env` value).
# This avoids the surprising behavior where a caller does not have RACK_ENV set,
# they call +Dotenviable.load+, and RACK_ENV is still not set,
# though it had some implied usage within this method.
# If for some reason you do not want +ENV['RACK_ENV']+ to be set,
# you can store its value before calling `load` and set it back after.
#
# PORT variable: Foreman assigns the $PORT environment variable BEFORE we load config
# (get to what is defined in worker, like puma.rb), so even if we have it in the .env files,
# it won't get used, because .env files don't stomp what is already in the environment
# (we don't want to use `overload`).
# So we have some trickery to overwrite only PORT.
module Appydays::Dotenviable
  def self.load(rack_env: nil, default_rack_env: "development", env: ENV)
    original_port = env.delete("PORT")
    rack_env ||= env["RACK_ENV"] || default_rack_env
    paths = [
      ".env.#{rack_env}.local",
      ".env.#{rack_env}",
      ".env",
    ]
    Dotenv.load(*paths)
    env["PORT"] ||= original_port
    env["RACK_ENV"] ||= rack_env
  end
end
