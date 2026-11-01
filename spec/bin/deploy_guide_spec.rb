require "rails_helper"
require "open3"

RSpec.describe "bin/deploy-guide" do
  let(:app_root) { Rails.root.to_s }

  def run_guide(*args)
    Open3.capture3(RbConfig.ruby, File.join(app_root, "bin", "deploy-guide"), *args, chdir: app_root)
  end

  describe "with no arguments (non-interactive)" do
    it "lists every deployment target with a one-line description" do
      stdout, _stderr, status = run_guide

      expect(status).to be_success
      expect(stdout).to include("kamal")
      expect(stdout).to include("self-host")
      expect(stdout).to include("managed")
    end
  end

  describe "kamal target" do
    it "points at the canonical Kamal deployment docs" do
      stdout, _stderr, status = run_guide("kamal")

      expect(status).to be_success
      expect(stdout).to include("/docs/developer/deployment")
      expect(stdout).to include("config/deploy.yml")
    end
  end

  describe "self-host target" do
    it "covers host prerequisites on top of the Kamal docs" do
      stdout, _stderr, status = run_guide("self-host")

      expect(status).to be_success
      expect(stdout).to include("/docs/developer/deployment")
      expect(stdout).to include("Docker")
      expect(stdout).to include("80")
      expect(stdout).to include("443")
    end
  end

  describe "managed target" do
    it "states the portable contract and which Kamal artifacts to ignore" do
      stdout, _stderr, status = run_guide("managed")

      expect(status).to be_success
      expect(stdout).to include("RAILS_MASTER_KEY")
      expect(stdout).to include("storage/")
      expect(stdout).to include("/up")
      expect(stdout).to include("SOLID_QUEUE_IN_PUMA")
      expect(stdout).to include("config/deploy.yml")
      expect(stdout).to include(".kamal/")
      expect(stdout).to include("bin/kamal")
    end

    it "warns about the SQLite single-writer constraint" do
      stdout, _stderr, _status = run_guide("managed")

      expect(stdout).to match(/single.writer|exactly one/i)
    end
  end

  describe "outbound mail" do
    it "names the SMTP server and the credentials login for every target, since the preflight refuses to boot without them" do
      %w[kamal managed].each do |target|
        stdout, _stderr, _status = run_guide(target)

        expect(stdout).to include("SMTP_ADDRESS", "smtp.user_name", "smtp.password"), target
      end
    end
  end

  describe "unknown target" do
    it "fails with the list of valid targets" do
      _stdout, stderr, status = run_guide("kubernetes")

      expect(status).not_to be_success
      expect(stderr).to include("kamal")
      expect(stderr).to include("self-host")
      expect(stderr).to include("managed")
    end
  end

  describe "doc references" do
    it "only points at doc sections that exist" do
      deployment_doc = File.read(File.join(app_root, "app", "docs", "developer", "deployment.md"))

      expect(deployment_doc).to include("## Deploying without Kamal", "### 4. Configure outbound mail")
    end
  end
end
