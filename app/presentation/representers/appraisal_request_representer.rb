# frozen_string_literal: true

require 'roar/decorator'
require 'roar/json'
require_relative 'project_representer'

module CodePraise
  module Representer
    # Representer for appraisal request sent to worker queue
    # Includes full project info so worker doesn't need database access
    class AppraisalRequest < Roar::Decorator
      include Roar::JSON

      property :project, extend: Representer::Project, class: OpenStruct
      property :folder_path
      property :id
    end
  end
end
