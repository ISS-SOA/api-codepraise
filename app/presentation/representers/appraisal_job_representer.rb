# frozen_string_literal: true

require 'roar/decorator'
require 'roar/json'
require_relative 'project_representer'

module CodePraise
  module Representer
    # Representer for appraisal job sent to worker queue
    # Serializes/deserializes Messaging::AppraisalJob for SQS transport
    class AppraisalJob < Roar::Decorator
      include Roar::JSON

      property :project, extend: Representer::Project, class: OpenStruct
      property :folder_path
      property :id
    end
  end
end
