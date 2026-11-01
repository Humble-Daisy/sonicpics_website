# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"

RSpec.describe DatabaseBackup do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:service) { DatabaseBackup::Bucket.new(ActiveStorage::Service::DiskService.new(root: dir.join("bucket").to_s)) }
  let(:database) { dir.join("production.sqlite3") }
  let(:files) { dir.join("files").tap(&:mkpath) }
  let(:backup) { described_class.new(database: database, files: files, destination: service, deployment: "production") }

  def write_rows(path, *names)
    SQLite3::Database.new(path.to_s) do |db|
      db.execute("PRAGMA journal_mode = WAL")
      db.execute("CREATE TABLE IF NOT EXISTS people (name TEXT)")
      names.each { |name| db.execute("INSERT INTO people (name) VALUES (?)", [ name ]) }
    end
  end

  def names_in(path)
    db = SQLite3::Database.new(path.to_s)
    db.execute("SELECT name FROM people ORDER BY name").flatten.tap { db.close }
  end

  def upload_file(key, content)
    files.join(key[0..1], key[2..3]).tap(&:mkpath).join(key).write(content)
  end

  def entries_in(key)
    archive = dir.join("archive.tar.gz").tap { |path| path.binwrite(service.download(key)) }
    Zlib::GzipReader.open(archive) do |gzip|
      Gem::Package::TarReader.new(gzip).to_h { |entry| [ entry.full_name, entry.read ] }
    end
  end

  def upload_archive(key, entries)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        entries.each { |name, content| tar.add_file_simple(name, 0o644, content.bytesize) { |file| file.write(content) } }
      end
    end
    service.upload(key, StringIO.new(io.string))
  end

  after { FileUtils.rm_rf(dir) }

  describe "#take!" do
    it "uploads one archive holding a copy of the database that opens with its rows" do
      write_rows(database, "ada", "grace")

      key = backup.take!

      copy = dir.join("copy.sqlite3").tap { |path| path.binwrite(entries_in(key).fetch("database.sqlite3")) }
      expect(names_in(copy)).to eq(%w[ada grace])
    end

    it "puts the uploaded files in the same archive, and nothing else from the storage folder" do
      write_rows(database, "ada")
      upload_file("abcdefgh", "a photo")
      files.join("production_cache.sqlite3").write("not an upload")

      entries = entries_in(backup.take!)

      expect(entries.keys).to contain_exactly("database.sqlite3", "files/ab/cd/abcdefgh")
      expect(entries["files/ab/cd/abcdefgh"]).to eq("a photo")
    end

    it "files each backup under its deployment, by time, and points latest at it" do
      write_rows(database, "ada")

      travel_to Time.utc(2026, 11, 1, 14, 0, 5) do
        expect(backup.take!).to eq("backups/production/2026-11-01T140005Z.tar.gz")
      end
      expect(backup.latest).to eq("backups/production/2026-11-01T140005Z.tar.gz")
    end

    it "keeps one deployment's latest apart from another's" do
      write_rows(database, "ada")
      staging = described_class.new(database: database, files: files, destination: service, deployment: "staging")

      production_key = backup.take!
      staging.take!

      expect(backup.latest).to eq(production_key)
    end
  end

  describe ".destination" do
    it "is a folder when BACKUP_PATH names one, kept for BACKUP_RETENTION_DAYS" do
      destination = described_class.destination({ "BACKUP_PATH" => dir.to_s, "BACKUP_RETENTION_DAYS" => "7" })

      expect(destination).to be_a(DatabaseBackup::Folder)
      expect(destination.retention).to eq(7.days)
    end

    it "is the object_storage bucket when OBJECT_STORAGE_BUCKET names one" do
      expect(described_class.destination({ "OBJECT_STORAGE_BUCKET" => "app-backups" })).to be_a(DatabaseBackup::Bucket)
    end

    it "is nothing when neither is set, so backups are off" do
      expect(described_class.destination({})).to be_nil
    end
  end

  describe ".files_root" do
    it "is the folder the Disk service keeps uploads in" do
      allow(ActiveStorage::Blob).to receive(:service).and_return(ActiveStorage::Service::DiskService.new(root: files.to_s))

      expect(described_class.files_root).to eq(files)
    end

    it "is nothing when uploads live in a bucket, which keeps its own copies" do
      allow(ActiveStorage::Blob).to receive(:service).and_return(service)

      expect(described_class.files_root).to be_nil
    end
  end

  describe "pruning" do
    it "asks the destination to prune after each backup, keeping the new one" do
      write_rows(database, "ada")
      allow(service).to receive(:prune)

      key = backup.take!

      expect(service).to have_received(:prune).with("backups/production", keep: key)
    end
  end

  describe "#latest" do
    it "is nil before the first backup" do
      expect(backup.latest).to be_nil
    end
  end

  describe "#restore!" do
    it "puts the latest backup in place of the database and keeps the old file beside it" do
      write_rows(database, "ada")
      backup.take!
      write_rows(database, "mallory")

      set_aside = backup.restore!

      expect(names_in(database)).to eq(%w[ada])
      expect(names_in(set_aside)).to eq(%w[ada mallory])
    end

    it "brings back uploaded files that are missing" do
      write_rows(database, "ada")
      upload_file("abcdefgh", "a photo")
      backup.take!
      FileUtils.rm_rf(files.join("ab"))

      backup.restore!

      expect(files.join("ab/cd/abcdefgh").read).to eq("a photo")
    end

    it "writes files only inside the uploads folder, whatever the archive names" do
      write_rows(database, "ada")
      upload_archive("backups/production/crafted.tar.gz",
        "database.sqlite3" => database.binread, "files/../../escaped" => "x")

      backup.restore!("backups/production/crafted.tar.gz")

      expect(dir.join("escaped")).not_to exist
      expect(dir.parent.join("escaped")).not_to exist
    end

    it "removes the old database's WAL files, which belong to the file set aside" do
      write_rows(database, "ada")
      backup.take!
      FileUtils.touch([ "#{database}-wal", "#{database}-shm" ])

      backup.restore!

      expect(File.exist?("#{database}-wal")).to be(false)
      expect(File.exist?("#{database}-shm")).to be(false)
    end

    it "restores a named backup instead of the latest" do
      write_rows(database, "ada")
      first = backup.take!
      write_rows(database, "grace")
      travel 1.day do
        backup.take!
      end

      backup.restore!(first)

      expect(names_in(database)).to eq(%w[ada])
    end

    it "refuses a backup whose database isn't sound, and changes nothing" do
      write_rows(database, "ada")
      upload_archive("backups/production/broken.tar.gz",
        "database.sqlite3" => "not a database", "files/ab/cd/abcdefgh" => "a photo")

      expect { backup.restore!("backups/production/broken.tar.gz") }.to raise_error(DatabaseBackup::Corrupt)
      expect(names_in(database)).to eq(%w[ada])
      expect(files.join("ab/cd/abcdefgh")).not_to exist
    end

    it "refuses a file that isn't an archive at all" do
      write_rows(database, "ada")
      service.upload("backups/production/garbage.tar.gz", StringIO.new("garbage"))

      expect { backup.restore!("backups/production/garbage.tar.gz") }.to raise_error(DatabaseBackup::Corrupt)
      expect(names_in(database)).to eq(%w[ada])
    end

    it "refuses when there is no backup to restore" do
      write_rows(database, "ada")

      expect { backup.restore! }.to raise_error(DatabaseBackup::Missing, /no backup/i)
      expect(names_in(database)).to eq(%w[ada])
    end
  end
end
