# frozen_string_literal: true

source 'https://rubygems.org'
ruby File.read('.ruby-version').strip

# CONFIGURATION
gem 'figaro', '~> 1.0'
gem 'pry'
gem 'rack-test' # for testing and can also be used to diagnose in production
gem 'rake', '~> 13.0'

# PRESENTATION LAYER
gem 'multi_json', '~> 1.15'
gem 'ostruct', '~> 0.0'
gem 'roar', '~> 1.1'

# APPLICATION LAYER
# Web application related
gem 'base64'
gem 'logger', '~> 1.0'
gem 'puma', '~> 6.0' # TODO: update to 7.0
gem 'rack-session', '~> 0' # TODO: check if needed
gem 'roda', '~> 3.0'

# Controllers and services
gem 'dry-monads', '~> 1.0'
gem 'dry-transaction', '~> 0'
gem 'dry-validation', '~> 1.0'

# Caching
gem 'rack-cache', '~> 1.13'
gem 'redis', '~> 4.8'
gem 'redis-rack-cache', '~> 2.2'

# DOMAIN LAYER
# Validation
gem 'dry-struct', '~> 1.0'
gem 'dry-types', '~> 1.0'

# INFRASTRUCTURE LAYER
# Networking
gem 'http', '~> 5.0'
gem 'openssl', '~> 3.3.1' # resolves MacoOS CRL error: https://github.com/ruby/openssl/issues/949

# Database
gem 'hirb'
# gem 'hirb-unicode' # incompatible with new rubocop
gem 'sequel', '~> 5.0'

# Asynchronicity
gem 'aws-sdk-sqs', '~> 1.0'
gem 'concurrent-ruby', '~> 1.0'
gem 'shoryuken', '~> 6.0'

group :development, :test do
  gem 'sqlite3', '~> 1.0'
end

group :production do
  gem 'pg', '~> 1.0'
end

# TESTING
group :test do
  # API Unit/Integration/Acceptance Tests
  gem 'minitest', '~> 5.0'
  gem 'minitest-rg', '~> 5.0'
  gem 'simplecov', '~> 0.0'
  gem 'vcr', '~> 6.0'
  gem 'webmock', '~> 3.0'
end

# Development
group :development do
  gem 'flog'
  gem 'reek'
  gem 'rerun'
  gem 'rubocop'
  gem 'rubocop-minitest'
  gem 'rubocop-rake'
  gem 'rubocop-sequel'
end
