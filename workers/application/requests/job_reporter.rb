# frozen_string_literal: true

# Note: ProgressPublisher is loaded via require_worker (infrastructure/messaging)

module GitClone
  # Reports job progress to client
  class JobReporter
    attr_reader :project, :folder_path

    def initialize(request_json, config)
      request = parse_request(request_json)

      @project = request.project
      @folder_path = request.respond_to?(:folder_path) ? (request.folder_path || '') : ''
      @publisher = ProgressPublisher.new(config, request.id)
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

    private

    # Parse request - handles both CloneRequest and AppraisalRequest formats
    def parse_request(request_json)
      parsed = JSON.parse(request_json)

      if parsed.key?('folder_path')
        # New AppraisalRequest format
        CodePraise::Representer::AppraisalRequest
          .new(OpenStruct.new)
          .from_json(request_json)
      else
        # Legacy CloneRequest format
        CodePraise::Representer::CloneRequest
          .new(OpenStruct.new)
          .from_json(request_json)
      end
    end
  end
end
