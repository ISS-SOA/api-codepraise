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

    def perform(_sqs_msg, request)
      job = JobReporter.new(request, Worker.config)
      perform_appraisal(job)
    rescue CodePraise::GitRepo::Errors::CannotOverwriteLocalGitRepo
      # worker should crash fail early - only catch errors we expect!
      puts 'CLONE EXISTS -- ignoring request'
    end

    private

    def perform_appraisal(job)
      gitrepo = CodePraise::GitRepo.new(job.project, Worker.config)

      Service::AppraiseProject.new.call(
        project: job.project,
        folder_path: job.folder_path,
        config: Worker.config,
        gitrepo: gitrepo,
        progress: job.progress_callback
      )

      # Keep sending finished status to any latecoming subscribers
      job.report_each_second(5) { AppraisalMonitor.finished_percent }
    end
  end
end
