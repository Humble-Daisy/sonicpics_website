require "rails_helper"
require "deploy_credentials"

RSpec.describe DeployCredentials do
  describe ".paths" do
    let(:root) { Pathname("/app") }

    it "leaves Rails to pick credentials by RAILS_ENV when the deploy names none" do
      expect(described_class.paths({}, root: root)).to eq({})
      expect(described_class.paths({ "RAILS_CREDENTIALS_ENV" => " " }, root: root)).to eq({})
    end

    it "points a staging deploy at the staging credentials and key" do
      expect(described_class.paths({ "RAILS_CREDENTIALS_ENV" => "staging" }, root: root)).to eq(
        content_path: Pathname("/app/config/credentials/staging.yml.enc"),
        key_path: Pathname("/app/config/credentials/staging.key")
      )
    end

    it "refuses a name that is not a plain credentials name" do
      expect { described_class.paths({ "RAILS_CREDENTIALS_ENV" => "../../tmp/x" }, root: root) }
        .to raise_error(ArgumentError, /RAILS_CREDENTIALS_ENV/)
    end
  end

  describe ".deployment" do
    it "names a deploy after its credentials, so staging and production keep their backups apart" do
      expect(described_class.deployment({ "RAILS_CREDENTIALS_ENV" => "staging" })).to eq("staging")
    end

    it "falls back to the Rails environment" do
      expect(described_class.deployment({})).to eq(Rails.env)
    end
  end
end
