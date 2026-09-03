# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch

  # Everything the gem ships has to be covered, whether a spec loads it or not.
  cover 'lib/**/*.rb'
  cover 'exe/**/*'

  # lib/templates holds the files the gem copies into an application. They are
  # sample content rather than library code, and settings.rb among them is only
  # ever `load`ed as data by KubernetesHelper.load_settings.
  skip 'lib/templates/'
  # Loaded by the gemspec, and therefore by bundler, before coverage starts.
  skip 'lib/kubernetes_helper/version.rb'

  minimum_coverage line: 100, branch: 100
end

# Before the gem, so that its `if defined?(Rails)` guard fires and the railtie is
# loaded and measured. railties is a development dependency for exactly this.
require 'rails'
require 'kubernetes_helper'
require 'byebug'
# tmpdir is a spec-only need; fileutils is required by the library itself.
require 'tmpdir'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Most examples work against the gem's own templates rather than an application
  # directory. An example that needs the real lookup stubs settings_path itself.
  config.before do
    path = File.join(__dir__, '../lib/templates')
    allow(KubernetesHelper).to receive(:settings_path) do |name = nil, **|
      name ? File.join(path, name) : path
    end
  end
end
