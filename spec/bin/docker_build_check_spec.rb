require "rails_helper"

# `load` defines the class without running it (bottom-of-file guard), as
# spec/bin/parallel_rspec_spec.rb does for its runner.
load Rails.root.join("bin/docker-build-check")

RSpec.describe DockerBuildCheck do
  let(:check) { described_class.new }

  it "builds the production image when the daemon answers" do
    allow(check).to receive(:system).with("docker", "info", any_args).and_return(true)
    expect(check).to receive(:system).with("docker", "build", any_args).and_return(true)

    expect { check.run }.to output(/Building the production image/).to_stdout
  end

  it "refuses the push, naming the fix and the rule, when the daemon is not running" do
    allow(check).to receive(:system).with("docker", "info", any_args).and_return(false)
    expect(check).not_to receive(:system).with("docker", "build", any_args)

    expect { check.run }
      .to raise_error(SystemExit) { |error| expect(error.status).not_to eq(0) }
      .and output(/DOCKER UNAVAILABLE.*fix:.*rule:/m).to_stderr
  end

  it "refuses the push when the image does not build" do
    allow(check).to receive(:system).with("docker", "info", any_args).and_return(true)
    allow(check).to receive(:system).with("docker", "build", any_args).and_return(false)

    expect { check.run }
      .to raise_error(SystemExit) { |error| expect(error.status).not_to eq(0) }
      .and output(/IMAGE BUILD FAILED.*fix:.*rule:/m).to_stderr
  end
end
