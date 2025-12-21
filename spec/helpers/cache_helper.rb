# frozen_string_literal: true

# Helper for Redis cache testing
# Uses real Redis with database 2 (test database) to avoid conflicts with:
# - Database 0: Rack::Cache (reverse proxy)
# - Database 1: Appraisal cache (production/development)
module CacheHelper
  # Create a cache instance for testing
  # Uses App.config which points to real Redis, but Cache::Remote
  # automatically uses database 2 when RACK_ENV=test
  def self.create_test_cache
    CodePraise::Cache::Remote.new(CodePraise::App.config)
  end

  # Wipe all keys from test cache
  def self.wipe_cache(cache = nil)
    cache ||= create_test_cache
    cache.wipe
  end
end
