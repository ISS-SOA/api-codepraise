# frozen_string_literal: true

require_relative '../../helpers/spec_helper'
require_relative '../../helpers/cache_helper'
require_relative '../../../workers/application/services/appraise_project'

describe 'Unit test of Appraiser::Service::AppraiseProject' do
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
      service = Appraiser::Service::AppraiseProject.new

      # Access private method for testing
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity).must_be_instance_of CodePraise::Entity::Project
      _(entity.name).must_equal 'test-project'
      _(entity.origin_id).must_equal 123
      _(entity.owner.username).must_equal 'testowner'
      _(entity.fullname).must_equal 'testowner/test-project'
    end

    it 'should handle empty contributors' do
      service = Appraiser::Service::AppraiseProject.new
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity.contributors).must_equal []
    end

    it 'should convert contributors' do
      @project_ostruct.contributors = [
        OpenStruct.new(origin_id: 789, username: 'contributor1', email: 'c1@example.com')
      ]

      service = Appraiser::Service::AppraiseProject.new
      entity = service.send(:build_project_entity, @project_ostruct)

      _(entity.contributors.length).must_equal 1
      _(entity.contributors.first.username).must_equal 'contributor1'
    end
  end

end

describe 'Unit test of CodePraise::CloneMapper' do
  it 'should map Cloning to :cloning_started' do
    _(CodePraise::CloneMapper.map('Cloning into...')).must_equal :cloning_started
  end

  it 'should map remote: to :cloning_remote' do
    _(CodePraise::CloneMapper.map('remote: Counting objects')).must_equal :cloning_remote
  end

  it 'should map Receiving to :cloning_receiving' do
    _(CodePraise::CloneMapper.map('Receiving objects: 50%')).must_equal :cloning_receiving
  end

  it 'should map Resolving to :cloning_resolving' do
    _(CodePraise::CloneMapper.map('Resolving deltas: 100%')).must_equal :cloning_resolving
  end

  it 'should map Checking to :cloning_done' do
    _(CodePraise::CloneMapper.map('Checking connectivity...')).must_equal :cloning_done
  end

  it 'should return nil for unknown lines' do
    _(CodePraise::CloneMapper.map('Unknown stage')).must_be_nil
  end

  it 'should return default for unknown lines with map_or_default' do
    _(CodePraise::CloneMapper.map_or_default('Unknown stage')).must_equal :cloning_started
  end

  it 'should return custom default when specified' do
    _(CodePraise::CloneMapper.map_or_default('Unknown', :custom)).must_equal :custom
  end
end

describe 'Unit test of Messaging::AppraisalJob' do
  it 'should create AppraisalJob struct' do
    project = OpenStruct.new(name: 'test')
    job = CodePraise::Messaging::AppraisalJob.new(project, 'app/models', 'request-123')

    _(job.project.name).must_equal 'test'
    _(job.folder_path).must_equal 'app/models'
    _(job.id).must_equal 'request-123'
  end
end

describe 'Unit test of Representer::AppraisalJob' do
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

    @job = CodePraise::Messaging::AppraisalJob.new(@project, 'app/models', 'req-123')
  end

  it 'should serialize to JSON' do
    json = CodePraise::Representer::AppraisalJob.new(@job).to_json
    parsed = JSON.parse(json)

    _(parsed['folder_path']).must_equal 'app/models'
    _(parsed['id']).must_equal 'req-123'
    _(parsed['project']['name']).must_equal 'test-project'
  end

  it 'should deserialize from JSON' do
    json = CodePraise::Representer::AppraisalJob.new(@job).to_json

    deserialized = CodePraise::Representer::AppraisalJob
      .new(OpenStruct.new)
      .from_json(json)

    _(deserialized.folder_path).must_equal 'app/models'
    _(deserialized.id).must_equal 'req-123'
    _(deserialized.project.name).must_equal 'test-project'
  end
end
