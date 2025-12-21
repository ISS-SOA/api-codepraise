# frozen_string_literal: true

require_relative '../../helpers/spec_helper'
require_relative '../../helpers/cache_helper'

describe 'Unit test of Cache::Remote' do
  before do
    @cache = CacheHelper.create_test_cache
    CacheHelper.wipe_cache(@cache)
  end

  after do
    CacheHelper.wipe_cache(@cache)
  end

  describe 'set and get' do
    it 'should store and retrieve a value' do
      @cache.set('test:key', 'hello world', ttl: 3600)

      _(@cache.get('test:key')).must_equal 'hello world'
    end

    it 'should return nil for non-existent key' do
      _(@cache.get('nonexistent')).must_be_nil
    end

    it 'should store JSON strings' do
      json = '{"status":"ok","data":{"count":42}}'
      @cache.set('json:key', json, ttl: 3600)

      result = @cache.get('json:key')
      _(result).must_equal json
      _(JSON.parse(result)['data']['count']).must_equal 42
    end
  end

  describe 'exists?' do
    it 'should return true for existing key' do
      @cache.set('exists:key', 'value', ttl: 3600)

      _(@cache.exists?('exists:key')).must_equal true
    end

    it 'should return false for non-existent key' do
      _(@cache.exists?('nonexistent')).must_equal false
    end
  end

  describe 'keys' do
    it 'should list all keys with test prefix' do
      @cache.set('key1', 'value1', ttl: 3600)
      @cache.set('key2', 'value2', ttl: 3600)

      keys = @cache.keys
      # In test environment, keys are prefixed with 'test:'
      _(keys).must_include 'test:key1'
      _(keys).must_include 'test:key2'
      _(keys.length).must_equal 2
    end
  end

  describe 'wipe' do
    it 'should remove all keys' do
      @cache.set('key1', 'value1', ttl: 3600)
      @cache.set('key2', 'value2', ttl: 3600)

      @cache.wipe

      _(@cache.keys).must_be_empty
      _(@cache.exists?('key1')).must_equal false
    end
  end
end
