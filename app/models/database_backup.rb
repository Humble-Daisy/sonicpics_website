# frozen_string_literal: true

require "rubygems/package"

class DatabaseBackup
  class Missing < StandardError; end
  class Corrupt < StandardError; end

  OFF = "Backups are off: set BACKUP_PATH to a folder, or OBJECT_STORAGE_BUCKET to a bucket. " \
        "/docs/developer/deployment (Back up the database)"
  DATABASE_ENTRY = "database.sqlite3"
  FILES_ENTRY = "files/"

  def self.destination(env = ENV)
    if env["BACKUP_PATH"].present?
      Folder.new(env["BACKUP_PATH"], retention: env.fetch("BACKUP_RETENTION_DAYS", 30).to_i.days, apart_from: Rails.root.join("storage"))
    elsif env["OBJECT_STORAGE_BUCKET"].present?
      Bucket.new
    end
  end

  def self.files_root
    service = ActiveStorage::Blob.service
    Pathname(service.root) if service.is_a?(ActiveStorage::Service::DiskService)
  end

  def initialize(database: Rails.root.join(ActiveRecord::Base.connection_db_config.database), files: self.class.files_root,
                 destination: self.class.destination, deployment: DeployCredentials.deployment)
    @database = Pathname(database)
    @files = files && Pathname(files)
    @destination = destination
    @prefix = "backups/#{deployment}"
  end

  def take!
    key = "#{@prefix}/#{timestamp}.tar.gz"

    Dir.mktmpdir do |dir|
      copy = File.join(dir, DATABASE_ENTRY)
      SQLite3::Database.new(@database.to_s) { |db| db.execute("VACUUM INTO ?", [ copy ]) }
      check_integrity!(copy)
      write_archive(File.join(dir, "backup.tar.gz"), copy)
      File.open(File.join(dir, "backup.tar.gz"), "rb") { |file| @destination.upload(key, file) }
    end

    @destination.upload(latest_pointer, StringIO.new(key))
    @destination.prune(@prefix, keep: key)
    key
  end

  def latest
    @destination.download(latest_pointer)
  rescue ActiveStorage::FileNotFoundError
    nil
  end

  def restore!(key = nil)
    key ||= latest or raise Missing, "There is no backup to restore under #{@prefix}."

    Dir.mktmpdir(nil, @database.dirname) do |dir|
      archive = File.join(dir, "backup.tar.gz")
      File.open(archive, "wb") { |file| @destination.download(key) { |chunk| file.write(chunk) } }
      restored = File.join(dir, DATABASE_ENTRY)
      each_entry(archive) { |entry| extract(entry, restored) if entry.full_name == DATABASE_ENTRY }
      check_integrity!(restored)
      restore_files(archive)

      set_aside_current.tap { File.rename(restored, @database) }
    end
  end

  private
    def latest_pointer = "#{@prefix}/latest"

    def timestamp = Time.current.utc.strftime("%Y-%m-%dT%H%M%SZ")

    def write_archive(archive, database_copy)
      Zlib::GzipWriter.open(archive) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          add(tar, DATABASE_ENTRY, database_copy)
          uploaded_files.each { |path| add(tar, "#{FILES_ENTRY}#{path.relative_path_from(@files)}", path) }
        end
      end
    end

    def add(tar, name, path)
      tar.add_file_simple(name, 0o644, File.size(path)) { |io| File.open(path, "rb") { |file| IO.copy_stream(file, io) } }
    end

    # The Disk service keeps each upload under two two-character folders; the databases sit beside them.
    def uploaded_files
      return [] unless @files&.directory?

      @files.glob("??/??/**/*").select(&:file?)
    end

    def restore_files(archive)
      return unless @files

      each_entry(archive) do |entry|
        relative = entry.full_name.delete_prefix(FILES_ENTRY)
        next unless entry.file? && entry.full_name.start_with?(FILES_ENTRY) && inside_files?(relative)

        path = @files.join(relative)
        # An upload's key never changes, so a file already there is the same file.
        extract(entry, path.tap { |file| file.dirname.mkpath }) unless path.exist?
      end
    end

    def inside_files?(relative)
      relative.split("/").none? { |part| part.empty? || part == "." || part == ".." }
    end

    def each_entry(archive, &)
      Zlib::GzipReader.open(archive) { |gzip| Gem::Package::TarReader.new(gzip).each(&) }
    rescue Zlib::Error, Gem::Package::TarInvalidError => error
      raise Corrupt, "#{archive} isn't a backup archive: #{error.message}"
    end

    def extract(entry, path)
      File.open(path, "wb") { |file| IO.copy_stream(entry, file) }
    end

    def check_integrity!(path)
      db = SQLite3::Database.new(path, readonly: true)
      result = db.get_first_value("PRAGMA integrity_check")
      raise Corrupt, "#{path} failed SQLite's integrity check: #{result}" unless result == "ok"
    rescue SQLite3::Exception => error
      raise Corrupt, "#{path} isn't a sound SQLite database: #{error.message}"
    ensure
      db&.close
    end

    def set_aside_current
      Pathname("#{@database}.before-restore-#{timestamp}").tap do |set_aside|
        [ "", "-wal", "-shm" ].each do |suffix|
          File.rename("#{@database}#{suffix}", "#{set_aside}#{suffix}") if File.exist?("#{@database}#{suffix}")
        end
      end
    end
end
