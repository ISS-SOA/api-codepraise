# frozen_string_literal: true

require_relative '../../helpers/spec_helper'
require_relative '../../helpers/cache_helper'
require_relative '../../../workers/application/services/appraise_project'

describe 'Unit test of Worker::AppraiseProject' do
  before do
    @cache = CacheHelper.create_test_cache
    CacheHelper.wipe_cache(@cache)

    # Create test project OpenStruct (simulating deserialized JSON)
    @project_ostruct = OpenStruct.new(
      origin_id: 123,
      name: 'test-project',
      size: 100,
      ssh_url: 'git@github.com:testowner/test-project.git',
      http_url: 'https://github.com/testowner/test-project',
      fullname: 'testowner/test-project',
      owner: OpenStruct.new(
        origin_id: 456,
        username: 'testowner',
        email: 'test@example.com'
      ),
      contributors: []
    )

    @progress_calls = []
    @progress_callback = ->(percent) { @progress_calls << percent }
  end

  after do
    CacheHelper.wipe_cache(@cache)
  end

  describe 'build_project_entity helper' do
    it 'should convert OpenStruct to Entity::Project' do
      service = Worker::AppraiseProject.new

      # Access private method for testing
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity).must_be_instance_of CodePraise::Entity::Project
      _(entity.name).must_equal 'test-project'
      _(entity.origin_id).must_equal 123
      _(entity.owner.username).must_equal 'testowner'
      _(entity.fullname).must_equal 'testowner/test-project'
    end

    it 'should handle empty contributors' do
      service = Worker::AppraiseProject.new
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity.contributors).must_equal []
    end

    it 'should convert contributors' do
      @project_ostruct.contributors = [
        OpenStruct.new(origin_id: 789, username: 'contributor1', email: 'c1@example.com')
      ]

      service = Worker::AppraiseProject.new
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity.contributors.length).must_equal 1
      _(entity.contributors.first.username).must_equal 'contributor1'
    end
  end

  describe 'scale_clone_progress helper' do
    it 'should scale Cloning to 25' do
      service = Worker::AppraiseProject.new
      _(service.send(:scale_clone_progress, 'Cloning into...')).must_equal 25
    end

    it 'should scale Receiving to 40' do
      service = Worker::AppraiseProject.new
      _(service.send(:scale_clone_progress, 'Receiving objects: 50%')).must_equal 40
    end

    it 'should scale Checking to 50' do
      service = Worker::AppraiseProject.new
      _(service.send(:scale_clone_progress, 'Checking connectivity...')).must_equal 50
    end

    it 'should default unknown stages to 30' do
      service = Worker::AppraiseProject.new
      _(service.send(:scale_clone_progress, 'Unknown stage')).must_equal 30
    end
  end
end

describe 'Unit test of AppraisalRequest' do
  it 'should create AppraisalRequest struct' do
    project = OpenStruct.new(name: 'test')
    request = CodePraise::Response::AppraisalRequest.new(project, 'app/models', 'request-123')

    _(request.project.name).must_equal 'test'
    _(request.folder_path).must_equal 'app/models'
    _(request.id).must_equal 'request-123'
  end
end

describe 'Unit test of Representer::AppraisalRequest' do
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

    @request = CodePraise::Response::AppraisalRequest.new(@project, 'app/models', 'req-123')
  end

  it 'should serialize to JSON' do
    json = CodePraise::Representer::AppraisalRequest.new(@request).to_json
    parsed = JSON.parse(json)

    _(parsed['folder_path']).must_equal 'app/models'
    _(parsed['id']).must_equal 'req-123'
    _(parsed['project']['name']).must_equal 'test-project'
  end

  it 'should deserialize from JSON' do
    json = CodePraise::Representer::AppraisalRequest.new(@request).to_json

    deserialized = CodePraise::Representer::AppraisalRequest
      .new(OpenStruct.new)
      .from_json(json)

    _(deserialized.folder_path).must_equal 'app/models'
    _(deserialized.id).must_equal 'req-123'
    _(deserialized.project.name).must_equal 'test-project'
  end
end
