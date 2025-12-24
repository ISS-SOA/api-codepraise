# frozen_string_literal: true

module CodePraise
  module Request
    # Application value for an appraisal request
    # Parses route parameters and provides cache key generation
    class Appraisal
      CACHE_KEY_PREFIX = 'appraisal'

      def initialize(owner_name, project_name, request)
        @owner_name = owner_name
        @project_name = project_name
        @request = request
        @path = request.remaining_path
      end

      attr_reader :owner_name, :project_name

      def folder_name
        @folder_name ||= @path.empty? ? '' : @path[1..]
      end

      def project_fullname
        @request.captures.join '/'
      end

      # Cache key for this request (currently folder-specific, will become root-only)
      def cache_key
        "#{CACHE_KEY_PREFIX}:#{project_fullname}/#{folder_name}"
      end

      # Is this a request for the root folder?
      def root_request?
        folder_name.empty?
      end
    end
  end
end
