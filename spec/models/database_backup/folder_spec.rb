# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseBackup::Folder do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  let(:folder) { described_class.new(root) }

  after { FileUtils.rm_rf(root) }

  it "stores each key at that path under the folder, so the backups can be browsed and copied by hand" do
    folder.upload("backups/production/2026-11-01T140005Z.tar.gz", StringIO.new("snapshot"))

    expect(root.join("backups/production/2026-11-01T140005Z.tar.gz").read).to eq("snapshot")
  end

  it "downloads what it stored, whole or in chunks" do
    folder.upload("backups/production/latest", StringIO.new("pointer"))

    expect(folder.download("backups/production/latest")).to eq("pointer")
    chunks = []
    folder.download("backups/production/latest") { |chunk| chunks << chunk }
    expect(chunks.join).to eq("pointer")
  end

  it "raises the same not-found error a bucket does" do
    expect { folder.download("backups/production/latest") }.to raise_error(ActiveStorage::FileNotFoundError)
  end

  it "prunes backups older than its retention, keeping the one just taken" do
    folder = described_class.new(root, retention: 30.days)
    names = %w[2026-09-01T000000Z 2026-10-15T000000Z 2026-11-01T140005Z].map { |time| "backups/production/#{time}.tar.gz" }
    names.each { |key| folder.upload(key, StringIO.new("x")) }

    travel_to Time.utc(2026, 11, 1, 15) do
      folder.prune("backups/production", keep: names.last)
    end

    expect(names.map { |key| root.join(key).exist? }).to eq([ false, true, true ])
  end

  it "never prunes another deployment's backups" do
    folder.upload("backups/staging/2026-01-01T000000Z.tar.gz", StringIO.new("x"))

    folder.prune("backups/production", keep: "backups/production/latest")

    expect(root.join("backups/staging/2026-01-01T000000Z.tar.gz")).to exist
  end

  it "still writes on the database's own disk, which covers a bad migration if not a lost disk" do
    folder = described_class.new(root, apart_from: root)

    folder.upload("backups/production/latest", StringIO.new("x"))

    expect(root.join("backups/production/latest")).to exist
  end

  it "says when it shares the database's disk, and so won't survive losing it" do
    expect(described_class.new(root, apart_from: root).caveat).to match(/same disk as the database/)
  end

  it "has nothing to say when it sits on another disk, or has nothing to compare with" do
    expect(described_class.new(root).caveat).to be_nil
  end
end
