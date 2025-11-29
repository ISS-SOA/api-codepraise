# frozen_string_literal: true

require_relative '../../helpers/spec_helper'
require 'fileutils'

describe 'Unit test of LocalCache' do
  before do
    # SAFETY: Create a mock config that returns a TEST cache directory
    # This prevents tests from touching the real cache at _cache/rack
    @test_cache_dir = 'spec/fixtures/test_cache'
    @config = Minitest::Mock.new
    @config.expect(:LOCAL_CACHE, @test_cache_dir)

    # When LocalCache.new(@config) is called, it will use @test_cache_dir
    # instead of the real LOCAL_CACHE value from secrets.yml
  end

  after do
    # Clean up the temporary test cache directory after each test
    # The real cache directory (_cache/rack) is never touched
    FileUtils.rm_rf(@test_cache_dir)
  end

  it 'should create cache directory if it does not exist' do
    CodePraise::Cache::Local.new(@config)

    _(Dir.exist?(@test_cache_dir)).must_equal true
  end

  it 'should list keys when cache has files' do
    cache = CodePraise::Cache::Local.new(@config)

    # Create some test files in the TEST directory
    meta_dir = "#{@test_cache_dir}/meta"
    body_dir = "#{@test_cache_dir}/body"
    FileUtils.mkdir_p(meta_dir)
    FileUtils.mkdir_p(body_dir)
    FileUtils.touch("#{meta_dir}/test1")
    FileUtils.touch("#{body_dir}/test2")

    keys = cache.keys

    _(keys.length).must_equal 2
    _(keys).must_include "#{meta_dir}/test1"
    _(keys).must_include "#{body_dir}/test2"
  end

  it 'should return empty array when no cache files exist' do
    cache = CodePraise::Cache::Local.new(@config)

    keys = cache.keys

    _(keys).must_be_empty
  end

  it 'should wipe all cache files' do
    cache = CodePraise::Cache::Local.new(@config)

    # Create some test files in the TEST directory
    meta_dir = "#{@test_cache_dir}/meta"
    body_dir = "#{@test_cache_dir}/body"
    FileUtils.mkdir_p(meta_dir)
    FileUtils.mkdir_p(body_dir)
    FileUtils.touch("#{meta_dir}/test1")
    FileUtils.touch("#{body_dir}/test2")

    # Verify files exist before wipe
    _(cache.keys.length).must_equal 2

    # Wipe cache - only affects TEST directory, not real cache
    cache.wipe

    # Verify files are gone
    _(cache.keys).must_be_empty
    # But directory should still exist (wipe removes contents, not directory)
    _(Dir.exist?(@test_cache_dir)).must_equal true
  end

  it 'should handle wipe when cache is already empty' do
    cache = CodePraise::Cache::Local.new(@config)

    # Should not raise error when wiping empty cache
    cache.wipe

    _(cache.keys).must_be_empty
  end
end
