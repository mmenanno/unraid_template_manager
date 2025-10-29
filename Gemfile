# frozen_string_literal: true

source "https://rubygems.org"

ruby "3.4.5"

# Core framework and platform integrations
gem "rails", "~> 8.1.1"
gem "propshaft"
gem "sqlite3", ">= 2.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Background processing, caching, and realtime
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Deployment and server
gem "thruster", require: false

# Performance
gem "bootsnap", require: false

# Diagnostics, tooling, and quality
group :development, :test, :ci do
  gem "debug", platforms: [:mri], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-shopify", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-minitest", require: false
  gem "rubocop-thread_safety", require: false
  gem "erb_lint", require: false
  gem "toys", "~> 0.15.6"
end

# System testing and HTTP mocking
group :test, :ci do
  gem "simplecov", require: false
  gem "mocha"
  gem "webmock"
  gem "capybara"
  gem "selenium-webdriver"
end

group :development do
  gem "web-console"
end

# Networking and parsing
gem "faraday"
gem "nokogiri"

# Diff functionality
gem "diffy"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: [:windows, :jruby]

gem "honeybadger", "~> 6.1"
