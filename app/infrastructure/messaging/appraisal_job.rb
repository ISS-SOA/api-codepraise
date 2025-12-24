# frozen_string_literal: true

module CodePraise
  module Messaging
    # Data Transfer Object for appraisal job sent to worker queue
    # Contains all data needed by worker to perform appraisal
    AppraisalJob = Struct.new(:project, :folder_path, :id)
  end
end
