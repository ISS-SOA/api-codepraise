# frozen_string_literal: true

# Note: ProgressPublisher is loaded via require_worker (infrastructure/messaging)

module Appraiser
  # Reports job progress to client
  class JobReporter
    attr_reader :project, :folder_path

    def initialize(job_json, config)
      job = CodePraise::Representer::AppraisalJob
        .new(OpenStruct.new)
        .from_json(job_json)

      @project = job.project
      @folder_path = job.folder_path || ''
      @publisher = ProgressPublisher.new(config, job.id)
    end

    def report(msg)
      @publisher.publish msg
    end

    def report_each_second(seconds, &operation)
      seconds.times do
        sleep(1)
        report(operation.call)
      end
    end

    # Returns a proc that can be passed to services for progress reporting
    def progress_callback
      ->(percent) { report(percent.to_s) }
    end
  end
end
