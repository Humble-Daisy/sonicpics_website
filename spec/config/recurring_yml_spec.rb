# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/recurring.yml", type: :config do
  let(:config) { ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")) }
  let(:production) { config.fetch("production") }

  it "schedules WorkspaceInvitationExpiringSweepJob every 6 hours" do
    entry = production.fetch("workspace_invitation_expiring_sweep")
    expect(entry["class"]).to eq("WorkspaceInvitationExpiringSweepJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to match(/every 6 hours/i)
  end

  it "schedules WorkspaceCapacitySweepJob every 12 hours" do
    entry = production.fetch("workspace_capacity_sweep")
    expect(entry["class"]).to eq("WorkspaceCapacitySweepJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to match(/every 12 hours/i)
  end

  it "backs up every day by default, on a schedule Solid Queue can read" do
    entry = production.fetch("database_backup")
    expect(entry["class"]).to eq("DatabaseBackupJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to eq("every day at 2am")
    expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
  end

  it "takes the backup schedule from BACKUP_SCHEDULE when it is set" do
    original = ENV["BACKUP_SCHEDULE"]
    ENV["BACKUP_SCHEDULE"] = "every hour"

    expect(production.dig("database_backup", "schedule")).to eq("every hour")
  ensure
    ENV["BACKUP_SCHEDULE"] = original
  end

  it "preserves the existing solid-queue clear-finished-jobs schedule" do
    entry = production.fetch("clear_solid_queue_finished_jobs")
    expect(entry["command"]).to include("SolidQueue::Job.clear_finished_in_batches")
  end
end
