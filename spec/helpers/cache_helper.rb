# frozen_string_literal: true

# Helper for Redis cache testing
# Uses real Redis with 'test:' key prefix for isolation from production data
module CacheHelper
  # Create a cache instance for testing
  # Uses App.config which points to real Redis, but Cache::Remote
  # automatically uses 'test:' key prefix when RACK_ENV=test
  def self.create_test_cache
    CodePraise::Cache::Remote.new(CodePraise::App.config)
  end

  # Wipe all keys from test cache
  def self.wipe_cache(cache = nil)
    cache ||= create_test_cache
    cache.wipe
  end
end
