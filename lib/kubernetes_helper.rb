# frozen_string_literal: true

require 'fileutils'
require 'kubernetes_helper/core'
require 'kubernetes_helper/cli'
# A single process takes exactly one side of this: the suite loads rails first, so
# the railtie is required and covered, and the plain-ruby arm cannot also run here.
# simplecov:disable branch
require 'kubernetes_helper/railtie' if defined?(Rails)
# simplecov:enable

module KubernetesHelper
  class Error < StandardError; end
  FOLDER_NAME = '.kubernetes'

  def self.settings(settings = nil)
    @settings = settings if settings
    @settings
  end

  # @param env_name (String)
  # @return [Hash]
  def self.load_settings # rubocop:disable Metrics/MethodLength:
    config_file = File.join(settings_path, 'settings.rb')
    load config_file

    def_settings = {
      cloud: {
        name: 'gcloud'
      },
      deployment: {
        log_container: true,
        log_folder: '/app/log',
        external_secrets: {},
        job_apps: settings[:job_apps] || job_apps_from_old_settings(settings)
      },
      service: {
        port_name: 'http-port',
        backend_port_name: 'b-port'
      },
      secrets: {},
      continuous_deployment: {},
      ingress: {}
    }
    deep_merge(def_settings, settings || {})
  end

  def self.deep_merge(hash1, hash2)
    merger = proc { |_key, v1, v2| v1.is_a?(Hash) && v2.is_a?(Hash) ? v1.merge(v2, &merger) : v2 }
    hash1.merge(hash2, &merger)
  end

  def self.settings_path(file_name = nil, use_template: false)
    path = File.join(Dir.pwd, FOLDER_NAME)
    if file_name
      app_path = File.join(path, file_name)
      path = use_template && !File.exist?(app_path) ? templates_path(file_name) : app_path
    end
    path
  end

  def self.run_cmd(cmd, title = nil)
    res = Kernel.system cmd
    Kernel.abort("::::::::CD: failed running command: #{title || cmd} ==> #{caller}") if res != true
  end

  def self.templates_path(file_name = nil)
    path = File.join(File.expand_path(__dir__), 'templates')
    file_name ? File.join(path, file_name) : path
  end

  # @param mode_or_file (basic, advanced, String) mode name or any specific template name
  def self.copy_templates(mode_or_file)
    FileUtils.mkdir(settings_path) unless Dir.exist?(settings_path)
    template_path = templates_path(mode_or_file)
    return FileUtils.cp(template_path, settings_path(mode_or_file)) if File.exist?(template_path)

    files = %w[README.md secrets.yml settings.rb]
    files += %w[deployment.yml cd.sh ingress.yml service.yml] if mode_or_file == 'advanced'
    files.each do |name|
      path = settings_path(name)
      FileUtils.cp(templates_path(name), path) unless File.exist?(path)
    end
  end

  # The older shape put one job app's settings directly on deployment as job_* keys. This
  # is the whole of that mapping, deliberately as a table rather than as a list of
  # assignments: rolling_update and min_ready_seconds were reachable through job_apps and
  # missing from here, so an application on the older keys could set them and nothing
  # happened at all. A table makes the next omission visible.
  #
  # The cron settings are absent on purpose. schedule, suspend and concurrency_policy only
  # do anything alongside kind: 'CronJob', which this shape cannot express, so an
  # application wanting a cronjob has to use job_apps.
  OLD_JOB_KEYS = {
    name: :job_name,
    command: :job_command,
    services: :job_services,
    resources: :job_resources,
    sidekiq_alive_gem: :job_sidekiq_alive_gem,
    rolling_update: :job_rolling_update,
    min_ready_seconds: :job_min_ready_seconds
  }.freeze

  def self.job_apps_from_old_settings(settings)
    deployment = settings[:deployment]
    return [] unless deployment[:job_name]

    [OLD_JOB_KEYS.to_h { |key, old_key| [key, deployment[old_key]] }]
  end
end
