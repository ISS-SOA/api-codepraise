# frozen_string_literal: true

# Helper for Redis cache testing
# Environment isolation via separate Redis databases:
#   - Test uses redis://localhost:6379/1 (configured in secrets.yml)
#   - Development uses redis://localhost:6379/0
module CacheHelper
  # Create a cache instance for testing
  def self.create_test_cache
    CodePraise::Cache::Remote.new(CodePraise::App.config)
  end

  # Wipe all keys from test cache
  def self.wipe_cache(cache = nil)
    cache ||= create_test_cache
    cache.wipe
  end
end
