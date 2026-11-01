require "rails_helper"

RSpec.describe DatabaseBackupJob, type: :job do
  let(:destination) { instance_double(DatabaseBackup::Folder, caveat: nil) }
  let(:backup) { instance_double(DatabaseBackup, take!: "backups/production/key.tar.gz") }

  before do
    allow(DatabaseBackup).to receive(:new).with(destination: destination).and_return(backup)
    allow(Rails.logger).to receive(:warn)
  end

  it "takes a backup to the configured destination" do
    allow(DatabaseBackup).to receive(:destination).and_return(destination)

    described_class.perform_now

    expect(backup).to have_received(:take!)
  end

  it "warns when the destination can't survive losing the server's disk" do
    allow(DatabaseBackup).to receive(:destination).and_return(destination)
    allow(destination).to receive(:caveat).and_return("same disk as the database")

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(/same disk as the database/)
  end

  it "warns and takes nothing when backups are off" do
    allow(DatabaseBackup).to receive(:destination).and_return(nil)

    described_class.perform_now

    expect(DatabaseBackup).not_to have_received(:new)
    expect(Rails.logger).to have_received(:warn).with(/Backups are off/)
  end

  it "runs on the default queue" do
    expect(described_class.queue_name).to eq("default")
  end
end
