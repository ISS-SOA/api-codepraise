# frozen_string_literal: true

require 'figaro'
require 'logger'
require 'rack/session'
require 'roda'
require 'sequel'

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
