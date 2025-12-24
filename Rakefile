# frozen_string_literal: true

require 'rake/testtask'
require_relative 'require_app'

task :default do
  puts `rake -T`
end

namespace :spec do
  # Internal tasks (no desc = hidden from rake -T)
  Rake::TestTask.new(:unit_integration) do |t|
    t.pattern = 'spec/tests/{unit,integration}/**/*_spec.rb'
    t.warning = false
    t.description = nil # Hide from rake -T
  end

  Rake::TestTask.new(:all_tests) do |t|
    t.pattern = 'spec/tests/**/*_spec.rb'
    t.warning = false
    t.description = nil # Hide from rake -T
  end

  desc 'Run all tests (unit + integration + acceptance) - requires worker running'
  task all: ['cache:ensure', :all_tests]
end

desc 'Run unit and integration tests (no worker required)'
task spec: ['cache:ensure', 'spec:unit_integration']

desc 'Keep rerunning unit/integration tests upon changes'
task :respec do
  sh "rerun -c 'rake spec' --ignore 'coverage/*' --ignore 'repostore/*'"
end

desc 'Run web app in default (dev) mode'
task run: ['run:dev']

namespace :run do
  desc 'Run API in dev mode'
  task :dev do
    sh 'bundle exec puma -p 9090'
  end

  desc 'Run API in test mode'
  task :test do
    sh 'RACK_ENV=test bundle exec puma -p 9090'
  end
end

desc 'Keep restarting web app in dev mode upon changes'
task :rerun do
  sh "rerun -c --ignore 'coverage/*' --ignore 'repostore/*'' -- bundle exec puma -p 9090"
end

namespace :db do
  task :config do # rubocop:disable Rake/Desc
    require 'sequel'
    require_relative 'config/environment' # load config info
    require_relative 'spec/helpers/database_helper'

    def app = CodePraise::App # rubocop:disable Rake/MethodDefinitionInTask
  end

  desc 'Run migrations'
  task :migrate => :config do
    Sequel.extension :migration
    puts "Migrating #{app.environment} database to latest"
    Sequel::Migrator.run(app.db, 'db/migrations')
  end

  desc 'Wipe records from all tables'
  task :wipe => :config do
    if app.environment == :production
      puts 'Do not damage production database!'
      return
    end

    require_app(%w[domain infrastructure])
    DatabaseHelper.wipe_database
  end

  desc 'Delete dev or test database file (set correct RACK_ENV)'
  task :drop => :config do
    if app.environment == :production
      puts 'Do not damage production database!'
      return
    end

    FileUtils.rm(app.config.DB_FILENAME)
    puts "Deleted #{app.config.DB_FILENAME}"
  end
end

namespace :repos do
  task :config do # rubocop:disable Rake/Desc
    require_relative 'config/environment' # load config info
    def app = CodePraise::App # rubocop:disable Rake/MethodDefinitionInTask
    @repo_dirs = Dir.glob("#{app.config.REPOSTORE_PATH}/*/")
  end

  desc 'Create directory for repo store'
  task :create => :config do
    puts `mkdir #{app.config.REPOSTORE_PATH}`
  end

  desc 'Delete cloned repos in repo store'
  task :wipe => :config do
    puts 'No git repositories found in repostore' if @repo_dirs.empty?

    sh "rm -rf #{app.config.REPOSTORE_PATH}/*/" do |ok, _|
      puts(ok ? "#{@repo_dirs.count} repos deleted" : 'Could not delete repos')
    end
  end

  desc 'List cloned repos in repo store'
  task :list => :config do
    if @repo_dirs.empty?
      puts 'No git repositories found in repostore'
    else
      puts @repo_dirs.join("\n")
    end
  end
end

namespace :cache do
  REDIS_CONTAINER = 'redis-codepraise'

  task :config do # rubocop:disable Rake/Desc
    require 'redis'
    require_relative 'config/environment'
    require_relative 'app/infrastructure/cache/remote_cache'
    @api = CodePraise::App
  end

  desc 'Check cache server connectivity'
  task status: :config do
    redis_url = @api.config.REDIS_URL
    puts "Environment: #{@api.environment}"
    puts "Checking cache at: #{redis_url}"
    redis = Redis.new(url: redis_url)
    response = redis.ping
    puts "Cache responded: #{response}"
    puts 'Cache connection successful!'
  rescue Redis::CannotConnectError => e
    puts "Cache connection FAILED: #{e.message}"
    puts ''
    puts 'To start Redis locally:'
    puts '  rake cache:redis:start'
    exit 1
  end

  desc 'Ensure cache is running (start if needed)'
  task :ensure do
    require 'redis'
    require_relative 'config/environment'
    redis_url = CodePraise::App.config.REDIS_URL

    redis = Redis.new(url: redis_url)
    redis.ping
    puts 'Cache is running'
  rescue Redis::CannotConnectError
    puts 'Cache not running, starting Redis container...'
    Rake::Task['cache:redis:start'].invoke
  end

  desc 'List all cached keys'
  task list: :config do
    puts "Environment: #{@api.environment}"
    keys = CodePraise::Cache::Remote.new(@api.config).keys
    if keys.none?
      puts 'No keys found'
    else
      keys.each { |key| puts "  #{key}" }
    end
  end

  desc 'Wipe all cached keys'
  task wipe: :config do
    env = @api.environment
    if env == :production
      print 'Are you sure you wish to wipe the PRODUCTION cache? (y/n) '
      return unless $stdin.gets.chomp.downcase == 'y'
    end

    puts "Wiping #{env} cache..."
    wiped = CodePraise::Cache::Remote.new(@api.config).wipe
    if wiped.empty?
      puts 'No keys to wipe'
    else
      wiped.each { |key| puts "  Wiped: #{key}" }
    end
  end

  # Redis-specific container management (for local development)
  namespace :redis do
    desc 'Start Redis Docker container'
    task :start do
      # Check if container exists
      container_exists = system("docker ps -a --format '{{.Names}}' | grep -q '^#{REDIS_CONTAINER}$'")

      if container_exists
        # Container exists, check if running
        container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{REDIS_CONTAINER}$'")
        if container_running
          puts "Redis container '#{REDIS_CONTAINER}' is already running"
        else
          puts "Starting existing Redis container '#{REDIS_CONTAINER}'..."
          sh "docker start #{REDIS_CONTAINER}"
        end
      else
        # Create and start new container
        puts "Creating and starting Redis container '#{REDIS_CONTAINER}'..."
        sh "docker run -d --name #{REDIS_CONTAINER} -p 6379:6379 redis:latest"
      end

      # Wait for Redis to be ready
      puts 'Waiting for Redis to be ready...'
      sleep 2
      Rake::Task['cache:status'].invoke
    end

    desc 'Stop Redis Docker container'
    task :stop do
      container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{REDIS_CONTAINER}$'")
      if container_running
        puts "Stopping Redis container '#{REDIS_CONTAINER}'..."
        sh "docker stop #{REDIS_CONTAINER}"
        puts 'Redis container stopped'
      else
        puts "Redis container '#{REDIS_CONTAINER}' is not running"
      end
    end

    desc 'Remove Redis Docker container'
    task :remove do
      Rake::Task['cache:redis:stop'].invoke
      container_exists = system("docker ps -a --format '{{.Names}}' | grep -q '^#{REDIS_CONTAINER}$'")
      if container_exists
        puts "Removing Redis container '#{REDIS_CONTAINER}'..."
        sh "docker rm #{REDIS_CONTAINER}"
        puts 'Redis container removed'
      else
        puts "Redis container '#{REDIS_CONTAINER}' does not exist"
      end
    end
  end
end

namespace :queues do
  task :config do # rubocop:disable Rake/Desc
    require 'aws-sdk-sqs'
    require_relative 'config/environment' # load config info
    @api = CodePraise::App
    @sqs = Aws::SQS::Client.new(
      access_key_id: @api.config.AWS_ACCESS_KEY_ID,
      secret_access_key: @api.config.AWS_SECRET_ACCESS_KEY,
      region: @api.config.AWS_REGION
    )
    @q_name = @api.config.WORKER_QUEUE
    puts "Environment: #{@api.environment}"
  end

  task :get_url => :config do # rubocop:disable Rake/Desc
    @q_url = @sqs.get_queue_url(queue_name: @q_name).queue_url
  end

  desc 'Create SQS queue for worker'
  task :create => :config do
    result = @sqs.create_queue(queue_name: @q_name)

    puts 'Queue created:'
    puts "  Name: #{@q_name}"
    puts "  Region: #{@api.config.AWS_REGION}"
    puts "  URL: #{result.queue_url}"
  rescue StandardError => e
    puts "Error creating queue: #{e}"
  end

  desc 'Report status of queue for worker'
  task :status => :get_url do
    puts 'Queue info:'
    puts "  Name: #{@q_name}"
    puts "  Region: #{@api.config.AWS_REGION}"
    puts "  URL: #{@q_url}"
  rescue StandardError => e
    puts "Error finding queue: #{e}"
  end

  desc 'Purge messages in SQS queue for worker'
  task :purge => :get_url do
    @sqs.purge_queue(queue_url: @q_url)
    puts "Queue #{@q_name} purged"
  rescue StandardError => e
    puts "Error purging queue: #{e}"
  end
end

namespace :worker do
  namespace :run do
    desc 'Run the background cloning worker in development mode'
    task :dev => :config do
      sh 'RACK_ENV=development bundle exec shoryuken -r ./workers/application/controllers/worker.rb -C ./workers/shoryuken_dev.yml'
    end

    desc 'Run the background cloning worker in testing mode'
    task :test => :config do
      sh 'RACK_ENV=test bundle exec shoryuken -r ./workers/application/controllers/worker.rb -C ./workers/shoryuken_test.yml'
    end

    desc 'Run the background cloning worker in production mode'
    task :production => :config do
      sh 'RACK_ENV=production bundle exec shoryuken -r ./workers/application/controllers/worker.rb -C ./workers/shoryuken.yml'
    end
  end
end

desc 'Run application console'
task :console do
  sh 'pry -r ./load_all'
end

namespace :vcr do
  desc 'delete cassette fixtures'
  task :wipe do
    sh 'rm spec/fixtures/cassettes/*.yml' do |ok, _|
      puts(ok ? 'Cassettes deleted' : 'No cassettes found')
    end
  end
end

namespace :quality do
  only_app = 'config/ app/'

  desc 'run all static-analysis quality checks'
  task all: %i[rubocop reek flog]

  desc 'code style linter'
  task :rubocop do
    sh 'rubocop'
  end

  desc 'code smell detector'
  task :reek do
    sh "reek #{only_app}"
  end

  desc 'complexiy analysis'
  task :flog do
    sh "flog -m #{only_app}"
  end
end
