# frozen_string_literal: true

require 'fileutils'

module CodePraise
  module Cache
    # Local disk cache utility
    class Local
      def initialize(config)
        @cache_dir = config.LOCAL_CACHE
        ensure_cache_directory
      end

      def keys
        Dir.glob("#{@cache_dir}/**/*").select { |f| File.file?(f) }
      end

      def wipe
        FileUtils.rm_rf(Dir.glob("#{@cache_dir}/*"))
      end

      private

      def ensure_cache_directory
        FileUtils.mkdir_p(@cache_dir)
      end
    end
  end
end
