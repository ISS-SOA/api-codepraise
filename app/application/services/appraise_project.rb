# frozen_string_literal: true

require 'dry/transaction'

module CodePraise
  module Service
    # Analyzes contributions to a project
    class AppraiseProject
      include Dry::Transaction

      step :retrieve_remote_project
      step :clone_remote
      step :appraise_contributions

      private

      NO_PROJ_ERR = 'Project not found'
      DB_ERR = 'Having trouble accessing the database'
      CLONE_ERR = 'Could not clone this project'
      TOO_LARGE_ERR = 'Project is too large to clone'
      NO_FOLDER_ERR = 'Could not find that folder'

      def retrieve_remote_project(input)
        input[:project] = Repository::For.klass(Entity::Project).find_full_name(
          input[:requested].owner_name, input[:requested].project_name
        )

        if input[:project]
          Success(input)
        else
          Failure(Response::ApiResult.new(status: :not_found, message: NO_PROJ_ERR))
        end
      rescue StandardError
        Failure(Response::ApiResult.new(status: :internal_error, message: DB_ERR))
      end

      def clone_remote(input)
        gitrepo = GitRepo.new(input[:project])
        gitrepo.clone unless gitrepo.exists_locally?

        Success(input.merge(gitrepo:))
      rescue GitRepo::Errors::TooLargeToClone
        App.logger.warn "Project too large: #{input[:project].fullname} (#{input[:project].size} KB)"
        Failure(Response::ApiResult.new(status: :forbidden, message: TOO_LARGE_ERR))
      rescue StandardError => error
        App.logger.error error.backtrace.join("\n")
        Failure(Response::ApiResult.new(status: :internal_error, message: CLONE_ERR))
      end

      def appraise_contributions(input)
        input[:folder] = Mapper::Contributions
          .new(input[:gitrepo]).for_folder(input[:requested].folder_name)

        appraisal = Response::ProjectFolderContributions.new(input[:project], input[:folder])
        Success(Response::ApiResult.new(status: :ok, message: appraisal))
      rescue StandardError
        App.logger.error "Could not find: #{full_request_path(input)}"
        Failure(Response::ApiResult.new(status: :not_found, message: NO_FOLDER_ERR))
      end

      # Helper methods

      def full_request_path(input)
        [input[:requested].owner_name,
         input[:requested].project_name,
         input[:requested].folder_name].join('/')
      end
    end
  end
end
