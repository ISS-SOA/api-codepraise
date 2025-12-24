# frozen_string_literal: true

require 'ostruct'
require 'roar/decorator'
require 'roar/json'

require_relative 'project_representer'
require_relative 'folder_contributions_representer'

module CodePraise
  module Representer
    # Represents appraisal result with status wrapper
    # Success: { "status": "ok", "project": {...}, "folder": {...} }
    # Error: { "status": "error", "project": {...}, "error_type": "...", "message": "..." }
    class Appraisal < Roar::Decorator
      include Roar::JSON

      property :status, exec_context: :decorator
      property :project, extend: Representer::Project, class: OpenStruct
      property :folder_path

      # Success case: include folder contributions
      property :folder, extend: Representer::FolderContributions, class: OpenStruct,
                        if: ->(represented:, **) { represented.success? }

      # Error case: include error details
      property :error_type, if: ->(represented:, **) { represented.error? }
      property :error_message, as: :message, if: ->(represented:, **) { represented.error? }

      # Convert symbol status to string for JSON
      def status
        represented.status.to_s
      end

      # Rebuilds appraisal JSON with an extracted folder
      # Used by smart cache to return subfolder from cached root appraisal
      def self.rebuild_with_extracted_folder(appraisal_json, folder_path, folder_ostruct)
        data = ::JSON.parse(appraisal_json)
        data['folder_path'] = folder_path
        data['folder'] = ::JSON.parse(FolderContributions.new(folder_ostruct).to_json)
        ::JSON.generate(data)
      rescue ::JSON::ParserError
        nil
      end
    end
  end
end
