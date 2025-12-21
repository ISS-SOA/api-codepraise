# frozen_string_literal: true

require 'fakeredis'

# Helper for Redis cache testing
# Provides in-memory Redis mock via fakeredis gem
module CacheHelper
  # Create a fake Redis-backed cache instance for testing
  # Returns a Cache::Remote that uses fakeredis (in-memory)
  def self.create_fake_cache
    config = OpenStruct.new(REDISCLOUD_URL: 'redis://localhost:6379/15')
    CodePraise::Cache::Remote.new(config)
  end

  # Wipe all keys from fake Redis
  def self.wipe_cache(cache)
    cache.wipe
  end
end
