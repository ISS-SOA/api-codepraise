# frozen_string_literal: true

require 'dry/transaction'

module CodePraise
  module Service
    # Fetches appraisal from cache or requests worker to create it
    # Does NOT perform appraisal - that's delegated to the worker
    class FetchOrRequestAppraisal
      include Dry::Transaction

      step :find_project_details
      step :check_project_eligibility
      step :check_cache
      step :request_appraisal_worker

      private

      NO_PROJ_ERR = 'Project not found'
      DB_ERR = 'Having trouble accessing the database'
      REQUEST_ERR = 'Could not request appraisal'
      TOO_LARGE_ERR = 'Project is too large to analyze'
      PROCESSING_MSG = 'Processing the appraisal request'

      # input hash keys expected: :requested, :request_id, :config
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
          Success(input)
        end
      end

      def check_cache(input)
        cache = Cache::Remote.new(input[:config])

        cached_json = cache.get(input[:requested].cache_key)
        return Success(input) unless cached_json

        # Cache hit - return the cached JSON directly
        # Mark as cache hit so controller knows to pass through
        input[:cached_json] = cached_json
        input[:cache_hit] = true
        Success(input)
      rescue StandardError => e
        # Cache errors should not fail the request - continue to worker
        App.logger.warn "Cache error: #{e.message}"
        Success(input)
      end

      def request_appraisal_worker(input)
        # If cache hit, we're done - return success with cached data
        return Success(input) if input[:cache_hit]

        # Cache miss - send job to worker
        Messaging::Queue.new(App.config.WORKER_QUEUE_URL, App.config)
          .send(appraisal_job_json(input))

        Failure(Response::ApiResult.new(
          status: :processing,
          message: { request_id: input[:request_id], msg: PROCESSING_MSG }
        ))
      rescue StandardError => e
        log_error(e)
        Failure(Response::ApiResult.new(status: :internal_error, message: REQUEST_ERR))
      end

      # Helper methods

      def appraisal_job_json(input)
        Messaging::AppraisalJob.new(
          input[:project],
          input[:requested].folder_name || '',
          input[:request_id]
        ).then { Representer::AppraisalJob.new(it).to_json }
      end

      def log_error(error)
        App.logger.error [error.inspect, error.backtrace].flatten.join("\n")
      end
    end
  end
end
