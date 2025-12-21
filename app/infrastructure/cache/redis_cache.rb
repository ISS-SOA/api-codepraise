# frozen_string_literal: true

require 'redis'

module CodePraise
  module Cache
    # Redis client utility for caching with TTL support
    # Uses key prefixes to separate namespaces:
    # - 'appraisal:' prefix for appraisal cache
    # - 'test:appraisal:' prefix for test environment
    # This avoids conflicts with Rack::Cache which uses its own key patterns
    class Remote
      def initialize(config)
        @redis = Redis.new(url: config.REDISCLOUD_URL)
        @key_prefix = ENV['RACK_ENV'] == 'test' ? 'test:' : ''
      end

      # Store a value with expiration
      # @param key [String] cache key
      # @param value [String] value to store (caller handles serialization)
      # @param ttl [Integer] time-to-live in seconds
      def set(key, value, ttl:)
        @redis.setex(prefixed(key), ttl, value)
      end

      # Retrieve a cached value
      # @param key [String] cache key
      # @return [String, nil] cached value or nil if not found/expired
      def get(key)
        @redis.get(prefixed(key))
      end

      # Check if a key exists
      # @param key [String] cache key
      # @return [Boolean] true if key exists
      def exists?(key)
        @redis.exists?(prefixed(key))
      end

      def keys
        @redis.keys("#{@key_prefix}*")
      end

      def wipe
        keys.each { |key| @redis.del(key) }
      end

      private

      def prefixed(key)
        "#{@key_prefix}#{key}"
      end
    end
  end
end
