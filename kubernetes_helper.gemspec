# frozen_string_literal: true

$:.push File.expand_path('lib', __dir__) # rubocop:disable Style/SpecialGlobalVars
require_relative 'lib/kubernetes_helper/version'

Gem::Specification.new do |spec|
  spec.name          = 'kubernetes_helper'
  spec.version       = KubernetesHelper::VERSION
  spec.authors       = %w[owen2345 notorious94]
  spec.email         = ['owenperedo@gmail.com']

  spec.summary       = 'Kubernetes helper to manage deployment files'
  spec.description   = 'Generates and applies Kubernetes manifests from a single settings file, ' \
                       'with templates for deployments, jobs, cronjobs, services, ingresses and secrets.'
  spec.homepage      = 'https://github.com/ReverseRetail/kubernetes_helper'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ReverseRetail/kubernetes_helper'
  spec.metadata['changelog_uri'] = 'https://github.com/ReverseRetail/kubernetes_helper'

  spec.files = Dir['{app,config,db,lib,exe}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # erb 4.0 dropped the trim_mode positional argument; nothing here passes one, and
  # the templates only need the standard tags, so any maintained release will do.
  spec.add_dependency 'erb', '>= 4.0'
  # ostruct stopped being a default gem in ruby 4.0, and KubernetesHelper::ErbBinding
  # is an OpenStruct, so without this the gem cannot even be required there.
  spec.add_dependency 'ostruct', '>= 0.6'

  spec.add_development_dependency 'byebug', '~> 13.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.90'
  spec.add_development_dependency 'simplecov', '~> 1.1'
  # Only so the railtie can be loaded and covered; railties ships rails.rb, which is
  # what lib/kubernetes_helper/railtie.rb requires.
  spec.add_development_dependency 'railties', '>= 7.0'
end
