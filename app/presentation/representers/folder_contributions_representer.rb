# frozen_string_literal: true

require 'ostruct'
require 'roar/decorator'
require 'roar/json'

require_relative 'contributor_representer'
require_relative 'credit_share_representer'
require_relative 'file_contributions_representer'
require_relative 'line_contribution_representer'

module CodePraise
  module Representer
    # Represents folder summary about repo's folder
    class FolderContributions < Roar::Decorator
      include Roar::JSON

      property :path
      property :line_count
      property :total_credits
      property :any_subfolders?
      property :any_base_files?
      property :credit_share, extend: Representer::CreditShare, class: OpenStruct
      collection :base_files, extend: Representer::FileContributions, class: OpenStruct
      collection :subfolders, extend: Representer::FolderContributions, class: OpenStruct
      collection :contributors, extend: Representer::Contributor, class: OpenStruct

      # Subfolder extraction methods for smart cache
      class << self
        # Extracts a subfolder from cached root JSON, returns OpenStruct or nil
        # @param json_string [String] Full appraisal JSON from cache
        # @param folder_path [String] Target folder path (e.g., "app/domain")
        # @return [OpenStruct, nil] The subfolder as OpenStruct, or nil if not found
        def extract_subfolder(json_string, folder_path)
          return nil if json_string.nil? || json_string.empty?

          appraisal = parse_appraisal(json_string)
          return nil unless appraisal&.folder

          normalized_path = normalize_path(folder_path)
          return appraisal.folder if normalized_path.empty?

          find_subfolder(appraisal.folder, normalized_path)
        end

        # Extracts a subfolder and returns it as JSON string
        # @param json_string [String] Full appraisal JSON from cache
        # @param folder_path [String] Target folder path
        # @return [String, nil] JSON string of subfolder, or nil if not found
        def extract_subfolder_json(json_string, folder_path)
          subfolder = extract_subfolder(json_string, folder_path)
          return nil unless subfolder

          new(subfolder).to_json
        end

        private

        # Parse appraisal JSON into hash/OpenStruct structure
        # Uses JSON.parse directly since Appraisal representer has serialization-only features
        def parse_appraisal(json_string)
          data = JSON.parse(json_string)
          return nil unless data['status'] == 'ok' && data['folder']

          # Parse the folder portion using FolderContributions representer
          folder_json = JSON.generate(data['folder'])
          folder = new(OpenStruct.new).from_json(folder_json)

          OpenStruct.new(status: data['status'], folder: folder)
        rescue JSON::ParserError
          nil
        end

        # Normalize folder path: remove leading/trailing slashes
        def normalize_path(path)
          path.to_s.gsub(%r{^/|/$}, '')
        end

        # Recursively find subfolder by path in the tree
        # @param folder [OpenStruct] Current folder node
        # @param target_path [String] Normalized target path
        # @return [OpenStruct, nil]
        def find_subfolder(folder, target_path)
          return nil unless folder.subfolders

          folder.subfolders.each do |subfolder|
            subfolder_path = normalize_path(subfolder.path)

            # Exact match
            return subfolder if subfolder_path == target_path

            # Check if target is nested within this subfolder
            if target_path.start_with?("#{subfolder_path}/")
              result = find_subfolder(subfolder, target_path)
              return result if result
            end
          end

          nil
        end
      end
    end
  end
end
