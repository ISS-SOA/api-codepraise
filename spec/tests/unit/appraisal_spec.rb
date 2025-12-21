# frozen_string_literal: true

require_relative '../../helpers/spec_helper'

describe 'Unit test of Value::Appraisal' do
  before do
    # Create minimal test fixtures
    @owner = CodePraise::Entity::Member.new(
      id: nil,
      origin_id: 123,
      username: 'testowner',
      email: 'test@example.com'
    )

    @project = CodePraise::Entity::Project.new(
      id: nil,
      origin_id: 456,
      name: 'test-project',
      size: 100,
      ssh_url: 'git@github.com:testowner/test-project.git',
      http_url: 'https://github.com/testowner/test-project',
      owner: @owner,
      contributors: []
    )
  end

  describe 'success factory method' do
    before do
      # Create a minimal folder contributions entity for success case
      # FolderContributions takes path: and files: (array of FileContributions)
      @folder = CodePraise::Entity::FolderContributions.new(
        path: '',
        files: []
      )

      @appraisal = CodePraise::Value::Appraisal.success(
        project: @project,
        folder_path: '',
        folder: @folder
      )
    end

    it 'should create a success appraisal' do
      _(@appraisal.success?).must_equal true
      _(@appraisal.error?).must_equal false
    end

    it 'should have :ok status' do
      _(@appraisal.status).must_equal :ok
    end

    it 'should include project' do
      _(@appraisal.project).must_equal @project
    end

    it 'should include folder contributions' do
      _(@appraisal.folder).must_equal @folder
    end

    it 'should have nil error fields' do
      _(@appraisal.error_type).must_be_nil
      _(@appraisal.error_message).must_be_nil
    end

    it 'should generate correct cache key' do
      _(@appraisal.cache_key).must_equal 'appraisal:testowner/test-project/'
    end

    it 'should return success TTL' do
      _(@appraisal.ttl).must_equal CodePraise::Value::Appraisal::SUCCESS_TTL
      _(@appraisal.ttl).must_equal 86_400
    end
  end

  describe 'error factory method' do
    before do
      @appraisal = CodePraise::Value::Appraisal.error(
        project: @project,
        folder_path: 'nonexistent/path',
        error_type: 'not_found',
        error_message: 'Folder does not exist'
      )
    end

    it 'should create an error appraisal' do
      _(@appraisal.error?).must_equal true
      _(@appraisal.success?).must_equal false
    end

    it 'should have :error status' do
      _(@appraisal.status).must_equal :error
    end

    it 'should include project' do
      _(@appraisal.project).must_equal @project
    end

    it 'should have nil folder' do
      _(@appraisal.folder).must_be_nil
    end

    it 'should include error details' do
      _(@appraisal.error_type).must_equal 'not_found'
      _(@appraisal.error_message).must_equal 'Folder does not exist'
    end

    it 'should generate correct cache key with folder path' do
      _(@appraisal.cache_key).must_equal 'appraisal:testowner/test-project/nonexistent/path'
    end

    it 'should return error TTL' do
      _(@appraisal.ttl).must_equal CodePraise::Value::Appraisal::ERROR_TTL
      _(@appraisal.ttl).must_equal 10
    end
  end

  describe 'immutability' do
    it 'should not allow attribute modification' do
      appraisal = CodePraise::Value::Appraisal.error(
        project: @project,
        folder_path: '',
        error_type: 'test',
        error_message: 'test'
      )

      # Dry::Struct instances are immutable - no setter methods exist
      _(appraisal.respond_to?(:status=)).must_equal false
      _(appraisal.respond_to?(:error_type=)).must_equal false
    end
  end
end

describe 'Unit test of Representer::Appraisal' do
  before do
    @owner = CodePraise::Entity::Member.new(
      id: nil,
      origin_id: 123,
      username: 'testowner',
      email: 'test@example.com'
    )

    @project = CodePraise::Entity::Project.new(
      id: nil,
      origin_id: 456,
      name: 'test-project',
      size: 100,
      ssh_url: 'git@github.com:testowner/test-project.git',
      http_url: 'https://github.com/testowner/test-project',
      owner: @owner,
      contributors: []
    )
  end

  # Note: Full success case serialization with FolderContributions is tested
  # in integration tests. Unit tests focus on the Appraisal wrapper behavior.

  describe 'error case serialization' do
    before do
      @appraisal = CodePraise::Value::Appraisal.error(
        project: @project,
        folder_path: 'bad/path',
        error_type: 'not_found',
        error_message: 'Folder not found'
      )

      @json = CodePraise::Representer::Appraisal.new(@appraisal).to_json
      @parsed = JSON.parse(@json)
    end

    it 'should serialize status as string' do
      _(@parsed['status']).must_equal 'error'
    end

    it 'should include project' do
      _(@parsed['project']).wont_be_nil
    end

    it 'should include folder_path' do
      _(@parsed['folder_path']).must_equal 'bad/path'
    end

    it 'should NOT include folder' do
      _(@parsed.key?('folder')).must_equal false
    end

    it 'should include error_type' do
      _(@parsed['error_type']).must_equal 'not_found'
    end

    it 'should include message (aliased from error_message)' do
      _(@parsed['message']).must_equal 'Folder not found'
    end
  end
end
