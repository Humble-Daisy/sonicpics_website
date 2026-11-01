require "rails_helper"
require "rake"

RSpec.describe "backup rake tasks" do
  before(:all) { RakeTasks.load_once }

  let(:destination) { instance_double(DatabaseBackup::Folder, caveat: nil) }
  let(:backup) { instance_double(DatabaseBackup) }

  before do
    allow(DatabaseBackup).to receive(:destination).and_return(destination)
    allow(DatabaseBackup).to receive(:new).with(destination: destination).and_return(backup)
  end

  it "backup:now takes a backup and names it" do
    allow(backup).to receive(:take!).and_return("backups/production/2026-11-01T140005Z.tar.gz")

    expect { RakeTasks.invoke("backup:now") }.to output(/backups\/production\/2026-11-01T140005Z\.tar\.gz/).to_stdout
  end

  it "backup:now stops with the fix when backups are off" do
    allow(DatabaseBackup).to receive(:destination).and_return(nil)

    expect { RakeTasks.invoke("backup:now") }.to raise_error(SystemExit).and output(/Backups are off/).to_stderr
  end

  it "backup:status names the latest backup" do
    allow(backup).to receive(:latest).and_return("backups/production/2026-11-01T140005Z.tar.gz")

    expect { RakeTasks.invoke("backup:status") }.to output(/Latest: backups\/production\/2026-11-01T140005Z/).to_stdout
  end

  it "backup:status says so when there is none yet" do
    allow(backup).to receive(:latest).and_return(nil)

    expect { RakeTasks.invoke("backup:status") }.to output(/No backup yet/).to_stdout
  end

  it "backup:status says when backups are off" do
    allow(DatabaseBackup).to receive(:destination).and_return(nil)

    expect { RakeTasks.invoke("backup:status") }.to output(/Backups are off/).to_stdout
  end

  it "backup:status passes on the destination's caveat" do
    allow(destination).to receive(:caveat).and_return("same disk as the database")
    allow(backup).to receive(:latest).and_return("backups/production/2026-11-01T140005Z.tar.gz")

    expect { RakeTasks.invoke("backup:status") }.to output(/same disk as the database/).to_stdout
  end

  it "backup:restore restores the latest, or the backup it is given, and says where the old file went" do
    allow(backup).to receive(:restore!).and_return(Pathname("storage/production.sqlite3.before-restore"))

    expect { RakeTasks.invoke("backup:restore") }.to output(/before-restore/).to_stdout
    expect(backup).to have_received(:restore!).with(nil)

    RakeTasks.invoke("backup:restore", "backups/production/old.tar.gz")
    expect(backup).to have_received(:restore!).with("backups/production/old.tar.gz")
  end
end
