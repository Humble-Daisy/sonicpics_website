# frozen_string_literal: true

require "rails_helper"
require "kamal"

RSpec.describe ".kamal/secrets" do
  around do |example|
    original = ENV.fetch("RAILS_MASTER_KEY", nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, ".kamal"))
      FileUtils.cp(Dir[Rails.root.join(".kamal/secrets*")], File.join(dir, ".kamal"))
      FileUtils.mkdir_p(File.join(dir, "config/credentials"))
      File.write(File.join(dir, "config/credentials/production.key"), "key-from-file\n")
      File.write(File.join(dir, "config/credentials/staging.key"), "staging-key-from-file\n")
      Dir.chdir(dir) { example.run }
    end
  ensure
    original.nil? ? ENV.delete("RAILS_MASTER_KEY") : ENV["RAILS_MASTER_KEY"] = original
  end

  def master_key = Kamal::Secrets.new["RAILS_MASTER_KEY"]

  it "takes RAILS_MASTER_KEY from the deploy's environment first" do
    ENV["RAILS_MASTER_KEY"] = "key-from-env"

    expect(master_key).to eq("key-from-env")
  end

  it "falls back to the production key file when the environment has none" do
    ENV.delete("RAILS_MASTER_KEY")

    expect(master_key).to eq("key-from-file")
  end

  it "falls back to the key file when the environment's value is blank" do
    ENV["RAILS_MASTER_KEY"] = ""

    expect(master_key).to eq("key-from-file")
  end

  context "for the staging destination" do
    def master_key = Kamal::Secrets.new(destination: "staging")["RAILS_MASTER_KEY"]

    it "takes RAILS_MASTER_KEY from the deploy's environment first" do
      ENV["RAILS_MASTER_KEY"] = "key-from-env"

      expect(master_key).to eq("key-from-env")
    end

    it "falls back to the staging key file, never production's" do
      ENV.delete("RAILS_MASTER_KEY")

      expect(master_key).to eq("staging-key-from-file")
    end
  end
end
