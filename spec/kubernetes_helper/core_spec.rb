# frozen_string_literal: true

require 'spec_helper'
RSpec.describe KubernetesHelper::Core do
  let(:settings) { { sample: { value1: 'sample value1' } } }
  let(:sample_yml) { custom_sample_yml rescue 'name: "<%= sample.value1 %>"' }
  let(:mock_file) { double('File', write: true, '<<' => true) }
  let(:output_yml) { 'file2.yml' }
  let(:inst) { described_class.new('beta') }

  before do
    allow(KubernetesHelper).to receive(:run_cmd)
    inst.config_values.merge!(settings)
    allow(File).to receive(:open).and_yield(mock_file)
    allow(File).to receive(:delete)
  end

  describe 'when parsing deployment yml file' do
    let(:mock_output_file) { double('File', write: true, '<<' => true) }
    let(:input_yml) { 'lib/templates/deployment.yml' }
    before do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:open).with(output_yml, anything).and_yield(mock_output_file)
    end
    after { |test| inst.parse_yml_file(input_yml, output_yml) unless test.metadata[:skip_after] }

    it 'parses provided yml file' do
      allow(File).to receive(:open).with(input_yml)
    end

    it 'saves parsed yml to provided path' do
      allow(File).to receive(:open).with(output_yml)
    end

    describe 'when defining secrets as env values' do
      describe 'when importing only secrets defined in secrets.yml (base 64 format)' do
        it 'includes all defined secrets in secrets.yml -> data' do
          allow(File).to receive(:read).with(/secrets.yml/) do
            <<~YML
              data:
                secret1: ''
                secret2: ''
            YML
          end
          inst.config_values[:secrets][:import_all_secrets] = false
          expect(mock_output_file).to receive(:write).with(include("name: SECRET1\n          valueFrom:"))
        end
      end

      describe 'when including all secrets (text plain format)' do
        it 'includes the setting to import all secrets (k8s auto imports all keys from the secrets)' do
          inst.config_values[:secrets][:import_all_secrets] = true
          secret_name = inst.config_values[:secrets][:name]
          expect(mock_output_file).to receive(:write).with(include("secretRef:\n            name: #{secret_name}"))
        end
      end

      describe 'when including defined env vars' do
        it 'includes static env vars' do
          inst.config_values[:deployment][:env_vars] = { ENV: 'production' }
          allow(mock_file).to receive(:write) do |content|
            expect(content).to include('name: ENV')
            expect(content).to include('value: production')
          end
        end

        it 'parses a complex external secret' do
          secrets = { PAPERTRAIL_PORT: { name: 'common_secrets', key: 'paper_trail_port' } }
          inst.config_values[:deployment][:env_vars] = secrets
          allow(mock_file).to receive(:write) do |content|
            expect(content).to include('name: PAPERTRAIL_PORT')
            expect(content).to include('name: common_secrets')
            expect(content).to include('key: paper_trail_port')
          end
        end
      end
    end

    describe 'when building the cloud sql proxy container' do
      # The v1 proxy is unusable: it checks the server certificate by matching its CN
      # against the literal "project:instance" string, and Cloud SQL serves DNS name
      # certificates now, so it fails every TLS handshake. These specs pin the v2
      # invocation, which differs in image, in entrypoint and in how the instance and
      # its port are passed.
      # export_documents writes one document at a time, so collect them all.
      def rendered
        content = +''
        allow(mock_output_file).to receive(:write) { |text| content << text }
        inst.parse_yml_file(input_yml, output_yml)
        content
      end

      it 'runs the v2 proxy' do
        expect(rendered).to include('image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.25.4')
      end

      it 'passes the flags through args, because v2 has its own entrypoint' do
        content = rendered
        expect(content).to include('--credentials-file=/secrets/gcloud/credentials.json')
        expect(content).not_to include('/cloud_sql_proxy')
        expect(content).not_to include('-instances=')
        expect(content).not_to include('-credential_file=')
      end

      it 'turns the =tcp: port of an instance into the v2 port query parameter' do
        inst.config_values[:deployment][:cloud_sql_instance] = 'proj:europe-west4:db=tcp:3306'

        expect(rendered).to include('- proj:europe-west4:db?port=3306')
      end

      it 'keeps accepting a comma separated list of instances' do
        inst.config_values[:deployment][:cloud_sql_instance] =
          'proj:europe-west4:mysql=tcp:3306, proj:europe-west3:pg=tcp:5432'
        content = rendered

        expect(content).to include('- proj:europe-west4:mysql?port=3306')
        expect(content).to include('- proj:europe-west3:pg?port=5432')
      end

      it 'leaves an instance that names no port alone' do
        inst.config_values[:deployment][:cloud_sql_instance] = 'proj:europe-west4:db'
        content = rendered

        expect(content).to include('- proj:europe-west4:db')
        expect(content).not_to include('?port=')
      end

      it 'gives the job pod the same proxy container' do
        inst.config_values[:deployment][:job_apps] = [{ name: 'pod1', command: 'cmd 1' }]

        # The job pod picks the container up through a YAML anchor, so one image bump
        # covers every pod kind. The anchor is resolved by the time the file is written,
        # hence counting the rendered container rather than looking for the reference.
        expect(rendered.scan('image: gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.25.4').size).to eq 2
      end
    end

    describe 'when building job pods' do
      it 'includes pod settings for all job pods', skip_after: true do
        settings = inst.config_values
        job_pods = [{ name: 'pod1', command: 'cmd 1' }, { name: 'pod2', command: 'cmd 2' }]
        settings[:deployment][:job_apps] = job_pods
        job_pods.each do |pod|
          allow(mock_file).to receive(:write).with(include("name: #{pod[:name]}"))
          allow(mock_file).to receive(:write).with(include(pod[:command]))
        end
        inst.parse_yml_file(input_yml, output_yml)
      end

      describe 'when building a cronjob app' do
        it 'generates the cronjob deployment yml content' do
          settings = inst.config_values
          settings[:deployment][:job_apps] = [{ name: 'pod1', kind: 'CronJob', schedule: '*' }]
          expect(mock_output_file).to receive(:write).with(include('concurrencyPolicy: Forbid'))
          expect(mock_output_file).to receive(:write).with(include('kind: CronJob'))
          inst.parse_yml_file(input_yml, output_yml)
        end
      end
    end
  end

  describe 'when running command' do
    it 'replaces config value' do
      expect(KubernetesHelper).to receive(:run_cmd).with('echo sample value1')
      inst.run_command('echo <%= sample.value1 %>')
    end
  end

  describe 'when executing bash file' do
    it 'replaces config value' do
      script_path = KubernetesHelper.settings_path('cd.sh')
      allow(File).to receive(:read).with(script_path).and_return('echo <%= sample.value1 %>')
      expect(File).to receive(:write).with(/tmp_script.sh$/, 'echo sample value1')
      inst.run_script(script_path)
    end
  end

  describe '#parse_documents' do
    # Reached through parse_yml_file in the rest of this file; called directly here
    # so the shapes a stream can take are each covered on their own.
    def parse(yml_data)
      inst.send(:parse_documents, yml_data)
    end

    it 'unwraps a documents list into the documents it holds' do
      expect(parse([{ 'documents' => [{ 'a' => 1 }, { 'b' => 2 }] }]))
        .to eq [{ 'a' => 1 }, { 'b' => 2 }]
    end

    it 'keeps a bare document as it is' do
      expect(parse([{ 'kind' => 'Deployment' }])).to eq [{ 'kind' => 'Deployment' }]
    end

    it 'drops the empty documents a trailing --- leaves in the stream' do
      expect(parse([nil, { 'kind' => 'Service' }, nil])).to eq [{ 'kind' => 'Service' }]
    end

    # Array(hash) splits a hash into key/value pairs rather than wrapping it, so the
    # Array() call tolerates nil but not a lone document. Nothing hits this in
    # practice: yml_data always comes from YAML.load_stream, which returns an array.
    it 'cannot take a lone document that did not arrive in an array' do
      expect { parse({ 'kind' => 'Ingress' }) }.to raise_error(TypeError)
    end
  end

  describe '#replace_config_variables' do
    it 'exposes a hash setting as an object the template can call methods on' do
      inst.config_values[:sample] = { value1: 'from a hash' }

      expect(inst.replace_config_variables('<%= sample.value1 %>')).to eq 'from a hash'
    end

    it 'passes a setting that is not a hash straight through' do
      inst.config_values[:plain] = 'a string'

      expect(inst.replace_config_variables('<%= plain %>')).to eq 'a string'
    end
  end
end
