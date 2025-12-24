# frozen_string_literal: true

require_relative '../../../require_app'
require_relative '../../../require_worker'

require_app      # Load API layers (domain, infrastructure, presentation, application)
require_worker   # Load worker-only layers (domain, infrastructure, presentation, application)

require 'figaro'
require 'shoryuken'

module Appraiser
  # Shoryuken worker class to clone repos and appraise contributions
  class Worker
    # Environment variables setup
    Figaro.application = Figaro::Application.new(
      environment: ENV['RACK_ENV'] || 'development',
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load
    def self.config = Figaro.env

    Shoryuken.sqs_client = Aws::SQS::Client.new(
      access_key_id: config.AWS_ACCESS_KEY_ID,
      secret_access_key: config.AWS_SECRET_ACCESS_KEY,
      region: config.AWS_REGION
    )

    include Shoryuken::Worker

    Shoryuken.sqs_client_receive_message_opts = { wait_time_seconds: 20 }
    shoryuken_options queue: config.WORKER_QUEUE_URL, auto_delete: true

    def perform(_sqs_msg, request_json)
      job = deserialize_job(request_json)
      progress_mapper = build_progress_mapper(job.id)

      perform_appraisal(job, progress_mapper)
    rescue CodePraise::GitRepo::Errors::CannotOverwriteLocalGitRepo
      # worker should crash fail early - only catch errors we expect!
      puts 'CLONE EXISTS -- ignoring request'
    end

    private

    def deserialize_job(request_json)
      CodePraise::Representer::AppraisalJob
        .new(OpenStruct.new)
        .from_json(request_json)
    end

    def build_progress_mapper(channel_id)
      faye_server = FayeServer.new(Worker.config, channel_id)
      ProgressMapper.new(faye_server)
    end

    def perform_appraisal(job, progress_mapper)
      gitrepo = CodePraise::GitRepo.new(job.project, Worker.config)

      Service::AppraiseProject.new.call(
        project: job.project,
        folder_path: job.folder_path || '',
        config: Worker.config,
        gitrepo: gitrepo,
        progress: progress_mapper.progress_callback
      )

      # Keep sending finished status to any latecoming subscribers
      progress_mapper.report_each_second(5, :finished)
    end
  end
end
