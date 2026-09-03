# frozen_string_literal: true

require 'spec_helper'
RSpec.describe KubernetesHelper do
  # .settings is module level state; hand it back untouched.
  def around_settings
    previous = described_class.settings
    yield
  ensure
    described_class.instance_variable_set(:@settings, previous)
  end

  describe 'when loading settings' do
    it 'loads the settings' do
      expect(KubernetesHelper.load_settings).to be_a(Hash)
    end

    it 'includes job_apps with data from old settings' do
      settings = {
        deployment: {
          job_name: 'job-name',
          job_resources: { test: true }
        }
      }
      res = described_class.job_apps_from_old_settings(settings)
      expect(res.first).to match(hash_including(name: 'job-name'))
      expect(res.first).to match(hash_including(resources: { test: true }))
    end

    it 'carries rolling_update and min_ready_seconds over from the old settings too' do
      # Both are reachable through job_apps and neither used to be mapped here, so an
      # application on the older job_name keys set them and nothing happened.
      settings = {
        deployment: {
          job_name: 'job-name',
          job_rolling_update: true,
          job_min_ready_seconds: 0
        }
      }
      res = described_class.job_apps_from_old_settings(settings)

      expect(res.first).to match(hash_including(rolling_update: true, min_ready_seconds: 0))
    end

    it 'leaves the cron settings out, which need a kind the old shape cannot express' do
      settings = { deployment: { job_name: 'job-name', job_schedule: '* * * * *' } }

      expect(described_class.job_apps_from_old_settings(settings).first.keys)
        .not_to include(:schedule, :kind)
    end
  end

  describe '.settings' do
    around { |example| around_settings { example.run } }

    it 'stores what it is given and answers with it afterwards' do
      described_class.settings(deployment: { name: 'app' })

      expect(described_class.settings).to eq(deployment: { name: 'app' })
    end

    it 'leaves what it holds alone when called with nothing' do
      described_class.settings(deployment: { name: 'app' })

      expect(described_class.settings(nil)).to eq(deployment: { name: 'app' })
    end
  end

  describe '.deep_merge' do
    it 'merges nested hashes instead of replacing them' do
      result = described_class.deep_merge(
        { deployment: { name: 'app', replicas: 1 } },
        { deployment: { replicas: 3 } }
      )

      expect(result).to eq(deployment: { name: 'app', replicas: 3 })
    end

    it 'lets a non hash on the right win outright' do
      expect(described_class.deep_merge({ a: { b: 1 } }, { a: 'plain' })).to eq(a: 'plain')
    end
  end

  describe '.settings_path' do
    # The suite stubs this globally, so these examples ask for the real thing.
    before { allow(described_class).to receive(:settings_path).and_call_original }

    it 'is the .kubernetes directory of the working directory' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.settings_path).to eq File.join(dir, '.kubernetes')
        end
      end
    end

    it 'points at the application copy of a named file' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.settings_path('deployment.yml'))
            .to eq File.join(dir, '.kubernetes', 'deployment.yml')
        end
      end
    end

    it 'falls back to the gem template when the application has no copy' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect(described_class.settings_path('deployment.yml', use_template: true))
            .to eq described_class.templates_path('deployment.yml')
        end
      end
    end

    it 'prefers the application copy over the template when both exist' do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          FileUtils.mkdir('.kubernetes')
          FileUtils.touch(File.join('.kubernetes', 'deployment.yml'))

          expect(described_class.settings_path('deployment.yml', use_template: true))
            .to eq File.join(dir, '.kubernetes', 'deployment.yml')
        end
      end
    end
  end

  describe '.templates_path' do
    it 'is the templates directory the gem ships' do
      expect(described_class.templates_path).to eq File.expand_path('../lib/templates', __dir__)
    end

    it 'joins a file name onto it' do
      expect(described_class.templates_path('cd.sh'))
        .to eq File.expand_path('../lib/templates/cd.sh', __dir__)
    end
  end

  describe '.run_cmd' do
    it 'runs the command and says nothing when it succeeds' do
      allow(Kernel).to receive(:system).with('echo hi').and_return(true)
      allow(Kernel).to receive(:abort)

      described_class.run_cmd('echo hi')

      expect(Kernel).not_to have_received(:abort)
    end

    it 'aborts naming the command when it fails' do
      allow(Kernel).to receive(:system).and_return(false)
      allow(Kernel).to receive(:abort)

      described_class.run_cmd('false')

      expect(Kernel).to have_received(:abort).with(/failed running command: false/)
    end

    it 'aborts with the title instead of the command when one is given' do
      allow(Kernel).to receive(:system).and_return(nil)
      allow(Kernel).to receive(:abort)

      described_class.run_cmd('kubectl apply -f secret.yml', 'apply secrets')

      expect(Kernel).to have_received(:abort).with(/failed running command: apply secrets/)
    end
  end

  describe '.copy_templates' do
    before { allow(described_class).to receive(:settings_path).and_call_original }

    def in_tmp_app
      Dir.mktmpdir { |dir| Dir.chdir(dir) { yield dir } }
    end

    it 'creates the .kubernetes directory when it is missing' do
      in_tmp_app do |dir|
        described_class.copy_templates('basic')

        expect(Dir.exist?(File.join(dir, '.kubernetes'))).to be true
      end
    end

    it 'leaves an existing .kubernetes directory alone' do
      in_tmp_app do
        FileUtils.mkdir('.kubernetes')
        allow(FileUtils).to receive(:mkdir)

        described_class.copy_templates('basic')

        expect(FileUtils).not_to have_received(:mkdir)
      end
    end

    it 'copies just the one file when asked for a named template' do
      in_tmp_app do |dir|
        described_class.copy_templates('cd.sh')

        expect(Dir.children(File.join(dir, '.kubernetes'))).to eq ['cd.sh']
      end
    end

    it 'copies the basic set when asked for a mode rather than a file' do
      in_tmp_app do |dir|
        described_class.copy_templates('basic')

        expect(Dir.children(File.join(dir, '.kubernetes')))
          .to contain_exactly('README.md', 'secrets.yml', 'settings.rb')
      end
    end

    it 'adds the deployment files on top for the advanced mode' do
      in_tmp_app do |dir|
        described_class.copy_templates('advanced')

        expect(Dir.children(File.join(dir, '.kubernetes')))
          .to contain_exactly('README.md', 'secrets.yml', 'settings.rb',
                              'deployment.yml', 'cd.sh', 'ingress.yml', 'service.yml')
      end
    end

    it 'does not overwrite a file the application has already edited' do
      in_tmp_app do |dir|
        FileUtils.mkdir('.kubernetes')
        settings = File.join(dir, '.kubernetes', 'settings.rb')
        File.write(settings, '# mine')

        described_class.copy_templates('basic')

        expect(File.read(settings)).to eq '# mine'
      end
    end
  end

  describe '.load_settings' do
    it 'takes job_apps straight from the settings when they are given' do
      # #load_settings re-runs the settings file, and the file's own
      # KubernetesHelper.settings call would replace what is injected here.
      around_settings do
        allow(described_class).to receive(:load)
        described_class.settings(deployment: {}, job_apps: [{ name: 'worker' }])

        expect(described_class.load_settings[:deployment][:job_apps]).to eq [{ name: 'worker' }]
      end
    end

    it 'is empty when neither job_apps nor the old job_name is set' do
      expect(described_class.job_apps_from_old_settings(deployment: {})).to eq []
    end
  end
end
