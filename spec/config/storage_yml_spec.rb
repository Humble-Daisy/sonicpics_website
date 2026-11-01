# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/storage.yml", type: :config do
  let(:service) { Rails.configuration.active_storage.service_configurations.fetch("object_storage") }

  it "defines an S3-compatible object_storage service for backups" do
    expect(service["service"]).to eq("S3")
  end

  it "reads the bucket's location from the environment and its key from the credentials" do
    source = Rails.root.join("config/storage.yml").read

    expect(source).to include('ENV["OBJECT_STORAGE_BUCKET"]', 'ENV["OBJECT_STORAGE_REGION"]', 'ENV["OBJECT_STORAGE_ENDPOINT"]')
    expect(source).to include("credentials.dig(:object_storage, :access_key_id)", "credentials.dig(:object_storage, :secret_access_key)")
  end

  it "builds an S3 service from it, so production can reach the bucket" do
    configs = { object_storage: service.merge("bucket" => "app-backups", "region" => "auto", "stub_responses" => true) }

    expect(ActiveStorage::Service.configure(:object_storage, configs)).to be_a(ActiveStorage::Service::S3Service)
  end
end
