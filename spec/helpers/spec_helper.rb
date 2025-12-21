# frozen_string_literal: true

ENV['RACK_ENV'] ||= 'test'

require 'simplecov'
SimpleCov.start

require 'yaml'

require 'minitest/autorun'
require 'minitest/unit' # minitest Github issue #17 requires
require 'minitest/rg'
require 'vcr'
require 'webmock'

require_relative '../../require_app'
require_relative '../../require_worker'

require_app              # Load API layers
require_worker('domain') # Load worker domain for tests using git infrastructure

USERNAME = 'soumyaray'
PROJECT_NAME = 'YPBT-app'
GITHUB_TOKEN = CodePraise::App.config.GITHUB_TOKEN
CORRECT = YAML.safe_load_file('spec/fixtures/github_results.yml')
