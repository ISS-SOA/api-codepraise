# frozen_string_literal: true

require_relative '../require_app'
require_relative 'clone_monitor'
require_relative 'job_reporter'
require_relative 'services/appraise_project'
require_app

require 'figaro'
require 'shoryuken'

module GitClone
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
    shoryuken_options queue: config.CLONE_QUEUE_URL, auto_delete: true

    def perform(_sqs_msg, request)
      job = JobReporter.new(request, Worker.config)

      if appraisal_request?(request)
        perform_appraisal(job)
      else
        perform_clone_only(job)
      end
    rescue CodePraise::GitRepo::Errors::CannotOverwriteLocalGitRepo
      # worker should crash fail early - only catch errors we expect!
      puts 'CLONE EXISTS -- ignoring request'
    end

    private

    # Check if this is the new AppraisalRequest format
    def appraisal_request?(request)
      JSON.parse(request).key?('folder_path')
    end

    # New flow: clone + appraise + cache
    def perform_appraisal(job)
      gitrepo = CodePraise::GitRepo.new(job.project, Worker.config)

      Worker::AppraiseProject.new.call(
        project: job.project,
        folder_path: job.folder_path,
        config: Worker.config,
        gitrepo: gitrepo,
        progress: job.progress_callback
      )

      # Keep sending finished status to any latecoming subscribers
      job.report_each_second(5) { AppraisalMonitor.finished_percent }
    end

    # Legacy flow: clone only (for backwards compatibility)
    def perform_clone_only(job)
      job.report(CloneMonitor.starting_percent)
      CodePraise::GitRepo.new(job.project, Worker.config).clone_locally do |line|
        job.report CloneMonitor.progress(line)
      end

      # Keep sending finished status to any latecoming subscribers
      job.report_each_second(5) { CloneMonitor.finished_percent }
    end
  end
end
