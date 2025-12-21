# frozen_string_literal: true

require 'rake/testtask'
require_relative 'require_app'

task :default do
  puts `rake -T`
end

desc 'Run unit and integration tests'
Rake::TestTask.new(:spec_only) do |t|
  t.pattern = 'spec/tests/**/*_spec.rb'
  t.warning = false
end

# Run specs with Redis check
task spec: ['redis:ensure', :spec_only]

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
  sh "rerun -c --ignore 'coverage/*' --ignore 'repostore/*' --ignore '_cache/*' -- bundle exec puma -p 9090"
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

namespace :redis do
  CONTAINER_NAME = 'redis-codepraise'

  task :config do # rubocop:disable Rake/Desc
    require 'redis'
    require_relative 'config/environment'
    @api = CodePraise::App
  end

  desc 'Check Redis connectivity'
  task status: :config do
    redis_url = @api.config.REDISCLOUD_URL
    puts "Checking Redis at: #{redis_url}"
    redis = Redis.new(url: redis_url)
    response = redis.ping
    puts "Redis responded: #{response}"
    puts 'Redis connection successful!'
  rescue Redis::CannotConnectError => e
    puts "Redis connection FAILED: #{e.message}"
    puts ''
    puts 'To start Redis locally:'
    puts '  rake redis:start'
    exit 1
  end

  desc 'Start Redis Docker container'
  task :start do
    # Check if container exists
    container_exists = system("docker ps -a --format '{{.Names}}' | grep -q '^#{CONTAINER_NAME}$'")

    if container_exists
      # Container exists, check if running
      container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{CONTAINER_NAME}$'")
      if container_running
        puts "Redis container '#{CONTAINER_NAME}' is already running"
      else
        puts "Starting existing Redis container '#{CONTAINER_NAME}'..."
        sh "docker start #{CONTAINER_NAME}"
      end
    else
      # Create and start new container
      puts "Creating and starting Redis container '#{CONTAINER_NAME}'..."
      sh "docker run -d --name #{CONTAINER_NAME} -p 6379:6379 redis:latest"
    end

    # Wait for Redis to be ready
    puts 'Waiting for Redis to be ready...'
    sleep 2
    Rake::Task['redis:status'].invoke
  end

  desc 'Stop Redis Docker container'
  task :stop do
    container_running = system("docker ps --format '{{.Names}}' | grep -q '^#{CONTAINER_NAME}$'")
    if container_running
      puts "Stopping Redis container '#{CONTAINER_NAME}'..."
      sh "docker stop #{CONTAINER_NAME}"
      puts 'Redis container stopped'
    else
      puts "Redis container '#{CONTAINER_NAME}' is not running"
    end
  end

  desc 'Remove Redis Docker container'
  task :remove do
    Rake::Task['redis:stop'].invoke
    container_exists = system("docker ps -a --format '{{.Names}}' | grep -q '^#{CONTAINER_NAME}$'")
    if container_exists
      puts "Removing Redis container '#{CONTAINER_NAME}'..."
      sh "docker rm #{CONTAINER_NAME}"
      puts 'Redis container removed'
    else
      puts "Redis container '#{CONTAINER_NAME}' does not exist"
    end
  end

  desc 'Ensure Redis is running (start if needed)'
  task :ensure do
    require 'redis'
    require_relative 'config/environment'
    redis_url = CodePraise::App.config.REDISCLOUD_URL

    redis = Redis.new(url: redis_url)
    redis.ping
    puts 'Redis is running'
  rescue Redis::CannotConnectError
    puts 'Redis not running, starting Docker container...'
    Rake::Task['redis:start'].invoke
  end
end

namespace :cache do
  task :config do # rubocop:disable Rake/Desc
    require_relative 'app/infrastructure/cache/local_cache'
    require_relative 'app/infrastructure/cache/redis_cache'
    require_relative 'config/environment' # load config info
    @api = CodePraise::App
  end

  desc 'Directory listing of local dev cache'
  namespace :list do
    desc 'Lists development cache'
    task :dev => :config do
      puts 'Lists development cache'
      keys = CodePraise::Cache::Local.new(@api.config).keys
      puts 'No local cache found' if keys.none?
      keys.each { |key| puts "Key: #{key}" }
    end

    desc 'Lists production cache'
    task :production => :config do
      puts 'Finding production cache'
      keys = CodePraise::Cache::Remote.new(@api.config).keys
      puts 'No keys found' if keys.none?
      keys.each { |key| puts "Key: #{key}" }
    end
  end

  namespace :wipe do
    desc 'Delete development cache'
    task :dev => :config do
      puts 'Deleting development cache'
      CodePraise::Cache::Local.new(@api.config).wipe
      puts 'Development cache wiped'
    end

    desc 'Delete production cache'
    task :production => :config do
      print 'Are you sure you wish to wipe the production cache? (y/n) '
      if $stdin.gets.chomp.downcase == 'y'
        puts 'Deleting production cache'
        wiped = CodePraise::Cache::Remote.new(@api.config).wipe
        wiped.each { |key| puts "Wiped: #{key}" }
      end
    end
  end
end

namespace :queues do
  task :config do
    require 'aws-sdk-sqs'
    require_relative 'config/environment' # load config info
    @api = CodePraise::App
    @sqs = Aws::SQS::Client.new(
      access_key_id: @api.config.AWS_ACCESS_KEY_ID,
      secret_access_key: @api.config.AWS_SECRET_ACCESS_KEY,
      region: @api.config.AWS_REGION
    )
    @q_name = @api.config.CLONE_QUEUE
    @q_url = @sqs.get_queue_url(queue_name: @q_name).queue_url

    puts "Environment: #{@api.environment}"
  end

  desc 'Create SQS queue for worker'
  task :create => :config do
    @sqs.create_queue(queue_name: @q_name)

    puts 'Queue created:'
    puts "  Name: #{@q_name}"
    puts "  Region: #{@api.config.AWS_REGION}"
    puts "  URL: #{@q_url}"
  rescue StandardError => e
    puts "Error creating queue: #{e}"
  end

  desc 'Report status of queue for worker'
  task :status => :config do
    puts 'Queue info:'
    puts "  Name: #{@q_name}"
    puts "  Region: #{@api.config.AWS_REGION}"
    puts "  URL: #{@q_url}"
  rescue StandardError => e
    puts "Error finding queue: #{e}"
  end

  desc 'Purge messages in SQS queue for worker'
  task :purge => :config do
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
      sh 'RACK_ENV=development bundle exec shoryuken -r ./workers/git_clone_worker.rb -C ./workers/shoryuken_dev.yml'
    end

    desc 'Run the background cloning worker in testing mode'
    task :test => :config do
      sh 'RACK_ENV=test bundle exec shoryuken -r ./workers/git_clone_worker.rb -C ./workers/shoryuken_test.yml'
    end

    desc 'Run the background cloning worker in production mode'
    task :production => :config do
      sh 'RACK_ENV=production bundle exec shoryuken -r ./workers/git_clone_worker.rb -C ./workers/shoryuken.yml'
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
