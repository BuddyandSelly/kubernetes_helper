# frozen_string_literal: true

require 'spec_helper'

# Loaded exactly once: ruby's Coverage only records a file's first compile, which is
# why the executable is a shim and the commands themselves live in
# KubernetesHelper::CLI, where each one gets its own example.
RSpec.describe 'exe/kubernetes_helper' do
  it 'hands the command line straight to the CLI' do
    allow(KubernetesHelper::CLI).to receive(:call)
    stub_const('ARGV', %w[generate_templates basic])

    load File.expand_path('../exe/kubernetes_helper', __dir__)

    expect(KubernetesHelper::CLI).to have_received(:call).with(%w[generate_templates basic])
  end
end
