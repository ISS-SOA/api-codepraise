# frozen_string_literal: true

require 'dry/transaction'

module Worker
  # Service to clone repo, appraise contributions, and cache result
  # Uses Dry::Transaction for composable steps with railway-oriented error handling
  class AppraiseProject
    include Dry::Transaction

    step :prepare_inputs
    step :clone_repo
    step :appraise_contributions
    step :cache_result

    private

    # Input: { project:, folder_path:, config:, gitrepo:, progress: }
    # project: OpenStruct from deserializing AppraisalRequest
    # folder_path: String path to folder being appraised
    # config: Worker config with Redis URL
    # gitrepo: GitRepo instance
    # progress: Proc to report progress

    def prepare_inputs(input)
      # Convert OpenStruct project to Entity::Project for Value::Appraisal
      input[:project_entity] = build_project_entity(input[:project])
      Success(input)
    rescue StandardError => e
      puts "PREPARE ERROR: #{e.message}"
      Failure(input.merge(error: { type: 'prepare_failed', message: e.message }))
    end

    def clone_repo(input)
      input[:progress].call(15) # STARTED

      if input[:gitrepo].exists_locally?
        input[:progress].call(50) # Skip to post-clone
      else
        input[:gitrepo].clone_locally do |line|
          # Scale clone progress from 15 to 50
          percent = scale_clone_progress(line)
          input[:progress].call(percent)
        end
      end

      Success(input)
    rescue StandardError => e
      # Create error appraisal and cache it
      input[:appraisal] = CodePraise::Value::Appraisal.error(
        project: input[:project_entity],
        folder_path: input[:folder_path],
        error_type: 'clone_failed',
        error_message: e.message
      )
      # Continue to cache the error
      Success(input)
    end

    def appraise_contributions(input)
      # Skip if already errored in clone step
      return Success(input) if input[:appraisal]&.error?

      input[:progress].call(55) # Starting appraisal

      folder = CodePraise::Mapper::Contributions
        .new(input[:gitrepo])
        .for_folder(input[:folder_path])

      input[:progress].call(85) # Appraisal complete

      # Build successful appraisal value object
      input[:appraisal] = CodePraise::Value::Appraisal.success(
        project: input[:project_entity],
        folder_path: input[:folder_path],
        folder: folder
      )

      Success(input)
    rescue StandardError => e
      # Create error appraisal
      input[:appraisal] = CodePraise::Value::Appraisal.error(
        project: input[:project_entity],
        folder_path: input[:folder_path],
        error_type: 'appraisal_failed',
        error_message: e.message
      )

      # Still cache the error - return Success to continue to cache_result
      Success(input)
    end

    def cache_result(input)
      input[:progress].call(90) # Caching

      appraisal = input[:appraisal]
      json = CodePraise::Representer::Appraisal.new(appraisal).to_json

      cache = CodePraise::Cache::Remote.new(input[:config])
      cache.set(appraisal.cache_key, json, ttl: appraisal.ttl)

      input[:progress].call(100) # FINISHED

      Success(input)
    rescue StandardError => e
      # Cache failure - still report 100% so client can retry
      puts "CACHE ERROR: #{e.message}"
      input[:progress].call(100)
      Success(input)
    end

    # Scale git clone progress (15-50 range)
    def scale_clone_progress(line)
      clone_stages = {
        'Cloning'   => 25,
        'remote'    => 35,
        'Receiving' => 40,
        'Resolving' => 45,
        'Checking'  => 50
      }

      first_word = line.match(/^[A-Za-z]+/).to_s
      clone_stages[first_word] || 30
    end

    # Convert OpenStruct project (from JSON) to Entity::Project
    def build_project_entity(project_ostruct)
      owner = build_member_entity(project_ostruct.owner)
      contributors = (project_ostruct.contributors || []).map { |c| build_member_entity(c) }

      CodePraise::Entity::Project.new(
        id: nil,
        origin_id: project_ostruct.origin_id,
        name: project_ostruct.name,
        size: project_ostruct.size,
        ssh_url: project_ostruct.ssh_url,
        http_url: project_ostruct.http_url,
        owner: owner,
        contributors: contributors
      )
    end

    # Convert OpenStruct member to Entity::Member
    def build_member_entity(member_ostruct)
      CodePraise::Entity::Member.new(
        id: nil,
        origin_id: member_ostruct.origin_id,
        username: member_ostruct.username,
        email: member_ostruct.email || ''
      )
    end
  end
end
