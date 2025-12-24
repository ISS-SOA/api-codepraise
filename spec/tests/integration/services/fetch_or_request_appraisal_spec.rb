# frozen_string_literal: true

require_relative '../../../helpers/spec_helper'
require_relative '../../../helpers/vcr_helper'
require_relative '../../../helpers/database_helper'
require_relative '../../../helpers/cache_helper'

require 'ostruct'

describe 'FetchOrRequestAppraisal Service Integration Test' do
  VcrHelper.setup_vcr

  before do
    VcrHelper.configure_vcr_for_github(recording: :none)
    DatabaseHelper.wipe_database
    @cache = CacheHelper.create_test_cache
    CacheHelper.wipe_cache(@cache)
    # Use App.config so the service uses the same Redis database as our test cache
    @config = CodePraise::App.config
  end

  after do
    VcrHelper.eject_vcr
    CacheHelper.wipe_cache(@cache)
  end

  describe 'Fetch or Request Appraisal' do
    it 'HAPPY: should return cached JSON when cache hit for root request' do
      # GIVEN: a valid project in database and cached appraisal
      gh_project = CodePraise::Github::ProjectMapper
        .new(GITHUB_TOKEN)
        .find(USERNAME, PROJECT_NAME)
      CodePraise::Repository::For.entity(gh_project).create(gh_project)

      # Pre-populate cache with appraisal JSON
      cache_key = "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      cached_json = File.read('spec/fixtures/json/sample_appraisal.json')
      @cache.set(cache_key, cached_json, ttl: 86_400)

      # WHEN: we request root appraisal
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: '',
        cache_key: cache_key
      )

      result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
        requested: request,
        request_id: 'test-123',
        config: @config
      )

      # THEN: we should get success with cached JSON (unchanged for root)
      _(result.success?).must_equal true
      _(result.value![:cache_hit]).must_equal true
      _(result.value![:cached_json]).must_equal cached_json
    end

    it 'HAPPY: should extract subfolder from cached root on cache hit' do
      # GIVEN: a valid project in database and cached root appraisal
      gh_project = CodePraise::Github::ProjectMapper
        .new(GITHUB_TOKEN)
        .find(USERNAME, PROJECT_NAME)
      CodePraise::Repository::For.entity(gh_project).create(gh_project)

      # Pre-populate cache with root appraisal JSON
      cache_key = "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      cached_json = File.read('spec/fixtures/json/sample_appraisal.json')
      @cache.set(cache_key, cached_json, ttl: 86_400)

      # WHEN: we request a subfolder appraisal
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: 'app',
        cache_key: cache_key
      )

      result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
        requested: request,
        request_id: 'test-123',
        config: @config
      )

      # THEN: we should get success with extracted subfolder JSON
      _(result.success?).must_equal true
      _(result.value![:cache_hit]).must_equal true

      # Verify extracted JSON contains the subfolder data
      extracted_data = JSON.parse(result.value![:cached_json])
      _(extracted_data['folder_path']).must_equal 'app'
      _(extracted_data['folder']['path']).must_equal 'app'
      _(extracted_data['folder']['line_count']).must_equal 500
    end

    it 'SAD: should return 404 when requested subfolder not found in cache' do
      # GIVEN: a valid project in database and cached root appraisal
      gh_project = CodePraise::Github::ProjectMapper
        .new(GITHUB_TOKEN)
        .find(USERNAME, PROJECT_NAME)
      CodePraise::Repository::For.entity(gh_project).create(gh_project)

      # Pre-populate cache with root appraisal JSON
      cache_key = "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      cached_json = File.read('spec/fixtures/json/sample_appraisal.json')
      @cache.set(cache_key, cached_json, ttl: 86_400)

      # WHEN: we request a non-existent subfolder
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: 'nonexistent/path',
        cache_key: cache_key
      )

      result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
        requested: request,
        request_id: 'test-123',
        config: @config
      )

      # THEN: we should get failure with not_found status
      _(result.failure?).must_equal true
      _(result.failure.status).must_equal :not_found
      _(result.failure.message).must_equal 'Folder not found in project'
    end

    it 'HAPPY: should return processing status when cache miss' do
      # GIVEN: a valid project in database but NO cached appraisal
      gh_project = CodePraise::Github::ProjectMapper
        .new(GITHUB_TOKEN)
        .find(USERNAME, PROJECT_NAME)
      CodePraise::Repository::For.entity(gh_project).create(gh_project)

      # WHEN: we request appraisal (cache is empty)
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: '',
        cache_key: "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      )

      # Mock the queue to avoid actual SQS calls
      mock_queue = Minitest::Mock.new
      mock_queue.expect(:send, nil, [String])

      CodePraise::Messaging::Queue.stub(:new, mock_queue) do
        result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
          requested: request,
          request_id: 'test-123',
          config: @config
        )

        # THEN: we should get failure with processing status
        _(result.failure?).must_equal true
        _(result.failure.status).must_equal :processing
        _(result.failure.message[:request_id]).must_equal 'test-123'
      end

      mock_queue.verify
    end

    it 'SAD: should not give appraisal for non-existent project' do
      # GIVEN: no project exists in database

      # WHEN: we request appraisal
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: '',
        cache_key: "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      )

      result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
        requested: request,
        request_id: 'test-123',
        config: @config
      )

      # THEN: we should get failure with not_found status
      _(result.failure?).must_equal true
      _(result.failure.status).must_equal :not_found
    end

    it 'SAD: should reject too large projects' do
      # GIVEN: a project that is too large
      gh_project = CodePraise::Github::ProjectMapper
        .new(GITHUB_TOKEN)
        .find(USERNAME, PROJECT_NAME)

      # Create a mock project that is too large
      large_project = CodePraise::Entity::Project.new(
        id: nil,
        origin_id: gh_project.origin_id,
        name: gh_project.name,
        size: 100_001, # Over 100MB limit
        ssh_url: gh_project.ssh_url,
        http_url: gh_project.http_url,
        owner: gh_project.owner,
        contributors: gh_project.contributors
      )
      CodePraise::Repository::For.entity(large_project).create(large_project)

      # WHEN: we request appraisal
      request = OpenStruct.new(
        owner_name: USERNAME,
        project_name: PROJECT_NAME,
        project_fullname: "#{USERNAME}/#{PROJECT_NAME}",
        folder_name: '',
        cache_key: "appraisal:#{USERNAME}/#{PROJECT_NAME}/"
      )

      result = CodePraise::Service::FetchOrRequestAppraisal.new.call(
        requested: request,
        request_id: 'test-123',
        config: @config
      )

      # THEN: we should get failure with forbidden status
      _(result.failure?).must_equal true
      _(result.failure.status).must_equal :forbidden
    end
  end
end
