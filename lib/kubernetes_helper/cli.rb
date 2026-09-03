# frozen_string_literal: true

module KubernetesHelper
  # The command line surface behind exe/kubernetes_helper.
  #
  # It lives here rather than in the executable because ruby's Coverage only
  # records a file's first compile: a script re-loaded to exercise a second
  # command reports nothing for it, so a case statement inside exe/ cannot be
  # measured. exe/kubernetes_helper is a shim that hands ARGV straight over.
  class CLI
    class << self
      # @param argv (Array<String>) the command name and its arguments
      # @param env (Hash) where DEPLOY_ENV is read from
      def call(argv, env = ENV)
        command, *args = argv
        case command
        when 'run_command' then run_command(args, env)
        when 'run_deployment', 'run_script' then run_script(args, env)
        when 'run_yml' then run_yml(args, env)
        when 'generate_templates' then generate_templates(args)
        when 'verify_yml' then verify_yml
        else puts 'Invalid command'
        end
      end

      private

      # Parses variables and runs the provided command.
      #   Sample: DEPLOY_ENV=beta kubernetes_helper run_command \
      #     "gcloud compute addresses create #{ingress.ip_name} --global"
      def run_command(args, env)
        core(env).run_command(args[0])
      end

      # Runs the deployment script.
      #   Sample: DEPLOY_ENV=beta kubernetes_helper run_deployment "cd.sh"
      def run_script(args, env)
        core(env).run_script(KubernetesHelper.settings_path(args[0], use_template: true))
      end

      # Parses kubernetes yml files, supporting multiple documents, config variable
      # replacement and included secrets, then applies the result.
      #   Sample: DEPLOY_ENV=beta kubernetes_helper run_yml "deployment.yml" "kubectl create"
      def run_yml(args, env)
        output_path = KubernetesHelper.settings_path('tmp_result.yml')
        core(env).parse_yml_file(KubernetesHelper.settings_path(args[0], use_template: true), output_path)
        KubernetesHelper.run_cmd("#{args[1]} -f #{output_path}")
      end

      # Generates the template files.
      #   Sample: kubernetes_helper generate_templates "basic"
      def generate_templates(args)
        KubernetesHelper.copy_templates(args[0] || 'basic')
      end

      # Verifies yml files for possible errors.
      # TODO: not implemented yet; recognised so it does not report an invalid command.
      def verify_yml; end

      def core(env)
        KubernetesHelper::Core.new(env['DEPLOY_ENV'])
      end
    end
  end
end
