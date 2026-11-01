# frozen_string_literal: true

require "rails_helper"
require "kamal"
require "commonmarker"

RSpec.describe "the deployment guide" do
  let(:guide) { Rails.root.join("app/docs/developer/deployment.md").read }
  let(:blocks) { ->(language) { guide.scan(/```#{language}\n(.*?)```/m).flatten } }
  let(:fenced) { ->(language, marker) { blocks.(language).find { |block| block.include?(marker) } } }
  let(:kamal_docs) { ->(name) { YAML.load_file(File.join(Gem.loaded_specs["kamal"].full_gem_path, "lib/kamal/configuration/docs/#{name}.yml"))[name] } }

  it "sets RAILS_HOST and the proxy before the step that deploys" do
    example = fenced.("yaml", "RAILS_HOST")

    expect(guide.index(example)).to be < guide.index("### 5. Point DNS, then deploy")
    expect(YAML.safe_load(example).dig("env", "clear", "RAILS_HOST")).to be_present
    expect(YAML.safe_load(example).dig("proxy", "ssl")).to be(true)
  end

  it "reads each deploy key through fnox in a form Kamal's secrets parser runs" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".kamal"))
      File.write(File.join(dir, ".kamal/secrets"), fenced.("bash", "fnox get").to_s)
      File.write(File.join(dir, ".kamal/secrets.staging"), fenced.("bash", "fnox --profile staging get").to_s)
      fnox = File.join(dir, "fnox")
      File.write(fnox, "#!/bin/sh\necho \"decrypted $*\"\n")
      File.chmod(0o755, fnox)

      path = ENV.fetch("PATH")
      production, staging = begin
        ENV["PATH"] = "#{dir}:#{path}"
        Dir.chdir(dir) { [ Kamal::Secrets.new["RAILS_MASTER_KEY"], Kamal::Secrets.new(destination: "staging")["RAILS_MASTER_KEY"] ] }
      ensure
        ENV["PATH"] = path
      end

      expect(production).to eq("decrypted get RAILS_MASTER_KEY")
      expect(staging).to eq("decrypted --profile staging get RAILS_MASTER_KEY")
    end
  end

  it "keeps production's key under a provider that staging's identities can't open" do
    stored = guide.scan(/^fnox set RAILS_MASTER_KEY --provider (\S+)(.*)$/)
    production = stored.reject { |_, rest| rest.include?("--profile") }.map(&:first)
    staging = stored.select { |_, rest| rest.include?("--profile staging") }.map(&:first)

    expect(production.size).to eq(1)
    expect(staging.size).to eq(1)
    expect(production).not_to eq(staging)
    expect(fenced.("toml", "recipients")).to include("[providers.#{production.first}]", "[providers.#{staging.first}]")
  end

  it "switches to ghcr.io with a registry block Kamal accepts" do
    example = YAML.safe_load(fenced.("yaml", "ghcr.io").to_s).to_h

    expect(example.dig("registry", "password")).to eq([ "KAMAL_REGISTRY_PASSWORD" ])
    expect {
      Kamal::Configuration::Validator::Registry.new(example["registry"], example: kamal_docs.("registry"), context: "registry").validate!
    }.not_to raise_error
  end

  it "shows a proxy behind another TLS terminator that Kamal accepts" do
    example = YAML.safe_load(fenced.("yaml", "http_port").to_s).to_h

    expect(example.dig("proxy", "ssl")).to be(false)
    expect {
      Kamal::Configuration::Validator::Proxy.new(example["proxy"], example: kamal_docs.("proxy"), context: "proxy").validate!
    }.not_to raise_error
  end

  it "pins every action it shows by commit SHA, with the version beside it" do
    uses = blocks.("yaml").join.scan(/uses: (\S+)(.*)$/)

    expect(uses).not_to be_empty
    expect(uses).to all(satisfy { |action, comment| action.match?(/@\h{40}\z/) && comment.match?(/# v\d/) })
  end

  it "names only backup tasks that exist" do
    require "rake"
    RakeTasks.load_once
    named = guide.scan(/bin\/rails '?(backup:\w+)/).flatten.uniq

    expect(named).to include("backup:now", "backup:status", "backup:restore")
    expect(named.reject { |task| Rake::Task.task_defined?(task) }).to be_empty
  end

  it "has every section the production preflight points to" do
    sections = Rails.root.join("config/initializers/required_production_config.rb").read.scan(%r{/docs/developer/deployment \((.+?) section\)}).flatten
    headings = guide.scan(/^#+ (?:\d+\. )?(.+)$/).flatten

    expect(sections).to include("Back up the database")
    expect(sections - headings).to be_empty
  end

  it "links only to headings it has" do
    ids = Commonmarker.to_html(guide, options: { extension: { header_ids: "", front_matter_delimiter: "---" } }).scan(/id="([^"]+)"/).flatten

    expect(guide.scan(/\]\(#([^)]+)\)/).flatten.uniq - ids).to be_empty
  end
end
