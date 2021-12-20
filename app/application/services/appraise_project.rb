# frozen_string_literal: true

require 'dry/transaction'

module CodePraise
  module Service
    # Analyzes contributions to a project
    class AppraiseProject
      include Dry::Transaction

      step :find_project_details
      step :check_project_eligibility
      step :request_cloning_worker
      step :appraise_contributions

      private

      # rubocop:disable Lint/UselessConstantScoping
      NO_PROJ_ERR = 'Project not found'
      DB_ERR = 'Having trouble accessing the database'
      CLONE_ERR = 'Could not clone this project'
      TOO_LARGE_ERR = 'Project is too large to analyze'
      NO_FOLDER_ERR = 'Could not find that folder'
      PROCESSING_MSG = 'Processing the appraisal request'
      # rubocop:enable Lint/UselessConstantScoping

      # input hash keys expected: :project, :requested, :config
      def find_project_details(input)
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

      def check_project_eligibility(input)
        if input[:project].too_large?
          Failure(Response::ApiResult.new(status: :forbidden, message: TOO_LARGE_ERR))
        else
          input[:gitrepo] = GitRepo.new(input[:project], input[:config])
          Success(input)
        end
      end

      def request_cloning_worker(input)
        return Success(input) if input[:gitrepo].exists_locally?

        Messaging::Queue.new(App.config.CLONE_QUEUE_URL, App.config)
          .send(clone_request_json(input))

          Failure(Response::ApiResult.new(
            status: :processing,
            message: { request_id: input[:request_id], msg: PROCESSING_MSG }
          ))
      rescue StandardError => e
        log_error(e)
        Failure(Response::ApiResult.new(status: :internal_error, message: CLONE_ERR))
      end

      def appraise_contributions(input)
        input[:folder] = Mapper::Contributions
          .new(input[:gitrepo]).for_folder(input[:requested].folder_name)

        appraisal = Response::ProjectFolderContributions.new(input[:project], input[:folder])
        Success(Response::ApiResult.new(status: :ok, message: appraisal))
      rescue StandardError
        # App.logger.error "Could not find: #{full_request_path(input)}"
        Failure(Response::ApiResult.new(status: :not_found, message: NO_FOLDER_ERR))
      end

      # Helper methods for steps

      def full_request_path(input)
        [input[:requested].owner_name,
         input[:requested].project_name,
         input[:requested].folder_name].join('/')
      end

      def log_error(error)
        App.logger.error [error.inspect, error.backtrace].flatten.join("\n")
      end

      def clone_request_json(input)
        Response::CloneRequest.new(input[:project], input[:request_id])
          .then { Representer::CloneRequest.new(_1) }
          .then(&:to_json)
      end
    end
  end
end
