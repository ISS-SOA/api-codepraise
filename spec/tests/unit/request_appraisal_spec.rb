# frozen_string_literal: true

require_relative '../../helpers/spec_helper'

describe 'Unit test of Request::Appraisal' do
  # Mock Roda request object with captures and remaining_path
  class MockRodaRequest
    attr_reader :captures, :remaining_path

    def initialize(captures:, remaining_path:)
      @captures = captures
      @remaining_path = remaining_path
    end
  end

  describe 'root folder request' do
    before do
      @mock_request = MockRodaRequest.new(
        captures: %w[testowner test-project],
        remaining_path: ''
      )

      @request = CodePraise::Request::Appraisal.new(
        'testowner', 'test-project', @mock_request
      )
    end

    it 'should parse owner_name' do
      _(@request.owner_name).must_equal 'testowner'
    end

    it 'should parse project_name' do
      _(@request.project_name).must_equal 'test-project'
    end

    it 'should have empty folder_name for root' do
      _(@request.folder_name).must_equal ''
    end

    it 'should compute project_fullname' do
      _(@request.project_fullname).must_equal 'testowner/test-project'
    end

    it 'should generate correct cache_key for root' do
      _(@request.cache_key).must_equal 'appraisal:testowner/test-project/'
    end

    it 'should identify as root request' do
      _(@request.root_request?).must_equal true
    end
  end

  describe 'subfolder request' do
    before do
      @mock_request = MockRodaRequest.new(
        captures: %w[testowner test-project],
        remaining_path: '/app/domain'
      )

      @request = CodePraise::Request::Appraisal.new(
        'testowner', 'test-project', @mock_request
      )
    end

    it 'should parse folder_name from remaining_path' do
      _(@request.folder_name).must_equal 'app/domain'
    end

    it 'should generate correct cache_key with folder' do
      _(@request.cache_key).must_equal 'appraisal:testowner/test-project/app/domain'
    end

    it 'should not identify as root request' do
      _(@request.root_request?).must_equal false
    end
  end

  describe 'nested subfolder request' do
    before do
      @mock_request = MockRodaRequest.new(
        captures: %w[ISS-SOA codepraise-api],
        remaining_path: '/app/domain/contributions/entities'
      )

      @request = CodePraise::Request::Appraisal.new(
        'ISS-SOA', 'codepraise-api', @mock_request
      )
    end

    it 'should handle deeply nested folder paths' do
      _(@request.folder_name).must_equal 'app/domain/contributions/entities'
    end

    it 'should generate correct cache_key for nested folder' do
      _(@request.cache_key).must_equal 'appraisal:ISS-SOA/codepraise-api/app/domain/contributions/entities'
    end
  end

  describe 'cache key format consistency' do
    it 'should match Value::Appraisal cache key format for root' do
      mock_request = MockRodaRequest.new(
        captures: %w[testowner test-project],
        remaining_path: ''
      )

      request = CodePraise::Request::Appraisal.new(
        'testowner', 'test-project', mock_request
      )

      # Both should produce same format: appraisal:{owner}/{project}/
      _(request.cache_key).must_equal 'appraisal:testowner/test-project/'
    end

    it 'should match Value::Appraisal cache key format for subfolder' do
      mock_request = MockRodaRequest.new(
        captures: %w[testowner test-project],
        remaining_path: '/some/path'
      )

      request = CodePraise::Request::Appraisal.new(
        'testowner', 'test-project', mock_request
      )

      # Both should produce same format: appraisal:{owner}/{project}/{folder}
      _(request.cache_key).must_equal 'appraisal:testowner/test-project/some/path'
    end
  end
end
