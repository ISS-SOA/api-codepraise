# frozen_string_literal: true

require 'dry-types'
require 'dry-struct'

# Require project entity (always available in API)
require_relative '../../projects/entities/project'

# Note: FolderContributions is loaded by the worker via workers/domain/contributions/
# The folder attribute uses duck typing - any object responding to expected methods

module CodePraise
  module Value
    # Value object representing the result of appraising a project folder
    # Immutable snapshot of appraisal outcome (success or error)
    class Appraisal < Dry::Struct
      include Dry.Types

      # Cache TTL constants
      SUCCESS_TTL = 86_400 # 1 day in seconds
      ERROR_TTL = 10       # 10 seconds

      # Status must be :ok or :error
      attribute :status, Strict::Symbol.enum(:ok, :error)

      # Project is always required (needed for cache key)
      attribute :project, Instance(Entity::Project)

      # Folder path being appraised (empty string for root)
      attribute :folder_path, Strict::String

      # Folder contributions (present on success, nil on error)
      # Uses Nominal type to accept any FolderContributions-like object
      attribute :folder, Nominal(Object).optional

      # Error details (present on error, nil on success)
      attribute :error_type, Strict::String.optional
      attribute :error_message, Strict::String.optional

      def success?
        status == :ok
      end

      def error?
        status == :error
      end

      def cache_key
        "appraisal:#{project.fullname}/#{folder_path}"
      end

      def ttl
        success? ? SUCCESS_TTL : ERROR_TTL
      end

      # Factory method for successful appraisal
      def self.success(project:, folder_path:, folder:)
        new(
          status: :ok,
          project:,
          folder_path:,
          folder:,
          error_type: nil,
          error_message: nil
        )
      end

      # Factory method for failed appraisal
      def self.error(project:, folder_path:, error_type:, error_message:)
        new(
          status: :error,
          project:,
          folder_path:,
          folder: nil,
          error_type:,
          error_message:
        )
      end
    end
  end
end
