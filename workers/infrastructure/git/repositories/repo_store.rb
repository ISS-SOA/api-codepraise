# frozen_string_literal: true

module CodePraise
  module Repository
    # Collection of all local git repo clones
    class RepoStore
      def self.all_repos
        Dir.glob(App.config.REPOSTORE_PATH + '/*')
          .select { File.directory?(_1) }
      end

      def self.wipe
        all_repos.each { |dir| FileUtils.rm_r(dir) }
      end
    end
  end
end
