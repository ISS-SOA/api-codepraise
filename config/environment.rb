# frozen_string_literal: true

require 'figaro'
require 'logger'
require 'rack/session'
require 'roda'
require 'sequel'
require 'rack/cache'
require 'redis-rack-cache'

module CodePraise
  # Environment-specific configuration
  class App < Roda
    plugin :environments

    # Environment variables setup
    Figaro.application = Figaro::Application.new(
      environment:,
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load
    def self.config = Figaro.env

    configure :development, :production do
      plugin :common_logger, $stderr
    end

    # Setup Cacheing mechanism
    configure :development do
      use Rack::Cache,
          verbose: true,
          metastore: "#{config.LOCAL_CACHE}/meta",
          entitystore: "#{config.LOCAL_CACHE}/body"
    end

    configure :production do
      puts 'RUNNING IN PRODUCTION MODE'
      # Set DATABASE_URL environment variable on production platform

      use Rack::Cache,
          verbose: true,
          metastore: "#{config.REDISCLOUD_URL}/0/metastore",
          entitystore: "#{config.REDISCLOUD_URL}/0/entitystore"
    end

    # Automated HTTP stubbing for testing only
    configure :app_test do
      require_relative '../spec/helpers/vcr_helper'
      VcrHelper.setup_vcr
      VcrHelper.configure_vcr_for_github(recording: :none)
    end

    # Database Setup (ensure DATABASE_URL already configured on production)
    configure :development, :test, :app_test do
      require 'pry'; # for breakpoints
      ENV['DATABASE_URL'] = "sqlite://#{config.DB_FILENAME}"
    end

    # Database Setup
    @db = Sequel.connect(ENV.fetch('DATABASE_URL'))
    def self.db = @db # rubocop:disable Style/TrivialAccessors

    # Logger Setup
    configure :development, :production do
      plugin :common_logger, $stderr
      @logger = Logger.new($stderr)
    end

    # Logger that outputs nowhere; used to suppress logging in test environment
    class NullLogger < Logger
      def initialize(*)
        super(IO::NULL)
      end
    end

    configure :test do
      plugin :common_logger, NullLogger.new
      @logger = NullLogger.new
    end

    class << self
      attr_reader :logger
    end
  end
end
