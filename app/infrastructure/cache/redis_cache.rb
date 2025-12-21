# frozen_string_literal: true

require 'redis'

module CodePraise
  module Cache
    # Redis client utility for caching with TTL support
    class Remote
      def initialize(config)
        @redis = Redis.new(url: config.REDISCLOUD_URL)
      end

      # Store a value with expiration
      # @param key [String] cache key
      # @param value [String] value to store (caller handles serialization)
      # @param ttl [Integer] time-to-live in seconds
      def set(key, value, ttl:)
        @redis.setex(key, ttl, value)
      end

      # Retrieve a cached value
      # @param key [String] cache key
      # @return [String, nil] cached value or nil if not found/expired
      def get(key)
        @redis.get(key)
      end

      # Check if a key exists
      # @param key [String] cache key
      # @return [Boolean] true if key exists
      def exists?(key)
        @redis.exists?(key)
      end

      def keys
        @redis.keys
      end

      def wipe
        keys.each { |key| @redis.del(key) }
      end
    end
  end
end
