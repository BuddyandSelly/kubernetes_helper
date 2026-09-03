# frozen_string_literal: true

require 'spec_helper'

RSpec.describe KubernetesHelper::Railtie do
  it 'registers itself under the gem name' do
    expect(described_class.railtie_name).to eq 'kubernetes_helper'
  end

  describe 'the rake_tasks block' do
    # Rails only runs these blocks while loading an application's rake tasks, so the
    # block is invoked directly here rather than booting one.
    let(:block) { described_class.instance_variable_get(:@rake_tasks).first }

    it 'loads every rake file found under the gem\'s lib/tasks' do
      # Stubbed rather than fixtured: the glob resolves to lib/tasks, which the gem
      # does not ship, so a real one would assert nothing at all. Worth knowing that
      # this block therefore loads nothing as things stand.
      files = %w[/gem/lib/tasks/one.rake /gem/lib/tasks/nested/two.rake]
      allow(Dir).to receive(:glob).and_return(files)
      loaded = []
      allow(described_class).to receive(:load) { |file| loaded << file }

      described_class.instance_exec(&block)

      expect(Dir).to have_received(:glob).with(%r{/kubernetes_helper/\.\./tasks/\*\*/\*\.rake\z})
      expect(loaded).to eq files
    end
  end
end
