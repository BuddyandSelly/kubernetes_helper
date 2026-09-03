# frozen_string_literal: true

require 'spec_helper'

RSpec.describe KubernetesHelper::CLI do
  let(:core) do
    instance_double(KubernetesHelper::Core, run_command: nil, run_script: nil, parse_yml_file: nil)
  end
  let(:env) { { 'DEPLOY_ENV' => 'beta' } }

  before do
    allow(KubernetesHelper::Core).to receive(:new).and_return(core)
    allow(KubernetesHelper).to receive(:run_cmd)
    allow(KubernetesHelper).to receive(:copy_templates)
  end

  describe 'run_command' do
    it 'builds the core for the deploy environment and runs the command through it' do
      described_class.call(['run_command', 'gcloud compute addresses create x'], env)

      expect(KubernetesHelper::Core).to have_received(:new).with('beta')
      expect(core).to have_received(:run_command).with('gcloud compute addresses create x')
    end
  end

  %w[run_deployment run_script].each do |command|
    describe command do
      it 'resolves the script, falling back to the gem template, and runs it' do
        described_class.call([command, 'cd.sh'], env)

        expect(KubernetesHelper).to have_received(:settings_path).with('cd.sh', use_template: true)
        expect(core).to have_received(:run_script).with(%r{/lib/templates/cd\.sh\z})
      end
    end
  end

  describe 'run_yml' do
    it 'parses the yml into a temporary file and applies that file' do
      described_class.call(['run_yml', 'deployment.yml', 'kubectl create'], env)

      expect(core).to have_received(:parse_yml_file)
        .with(%r{/lib/templates/deployment\.yml\z}, %r{tmp_result\.yml\z})
      expect(KubernetesHelper).to have_received(:run_cmd)
        .with(%r{\Akubectl create -f .*tmp_result\.yml\z})
    end
  end

  describe 'generate_templates' do
    it 'copies the mode it was given' do
      described_class.call(%w[generate_templates advanced], env)

      expect(KubernetesHelper).to have_received(:copy_templates).with('advanced')
    end

    it 'falls back to the basic mode when none is given' do
      described_class.call(['generate_templates'], env)

      expect(KubernetesHelper).to have_received(:copy_templates).with('basic')
    end
  end

  describe 'verify_yml' do
    # Recognised but not implemented; it must not fall through to the error.
    it 'does nothing rather than reporting an invalid command' do
      expect { described_class.call(['verify_yml'], env) }.not_to output.to_stdout
      expect(KubernetesHelper::Core).not_to have_received(:new)
    end
  end

  describe 'anything else' do
    it 'reports an invalid command' do
      expect { described_class.call(['nonsense'], env) }.to output("Invalid command\n").to_stdout
    end

    it 'reports an invalid command when called with no arguments at all' do
      expect { described_class.call([], env) }.to output("Invalid command\n").to_stdout
    end
  end

  describe 'the deploy environment' do
    it 'comes from ENV when no environment hash is passed' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DEPLOY_ENV').and_return('production')

      described_class.call(%w[run_command whoami])

      expect(KubernetesHelper::Core).to have_received(:new).with('production')
    end
  end
end
