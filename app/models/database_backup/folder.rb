# frozen_string_literal: true

class DatabaseBackup
  class Folder
    attr_reader :retention

    def initialize(root, retention: 30.days, apart_from: nil)
      @root = Pathname(root)
      @retention = retention
      @apart_from = apart_from && Pathname(apart_from)
    end

    def upload(key, io)
      path = @root.join(key)
      path.dirname.mkpath
      File.open("#{path}.partial", "wb") { |file| IO.copy_stream(io, file) }
      File.rename("#{path}.partial", path)
    end

    def download(key)
      path = @root.join(key)
      raise ActiveStorage::FileNotFoundError, key unless path.file?
      return path.binread unless block_given?

      path.open("rb") { |file| while (chunk = file.read(64.kilobytes)) do yield chunk end }
    end

    def prune(prefix, keep:)
      cutoff = retention.ago
      @root.glob("#{prefix}/*.tar.gz").each do |path|
        next if path == @root.join(keep)

        path.delete if taken_at(path) < cutoff
      end
    end

    def caveat
      return unless @apart_from && @root.exist? && @root.stat.dev == @apart_from.stat.dev

      "#{@root} is on the same disk as the database, so these backups won't survive losing that disk " \
        "(is the backup drive mounted?)."
    end

    private
      def taken_at(path)
        Time.find_zone("UTC").strptime(path.basename(".tar.gz").to_s, "%Y-%m-%dT%H%M%SZ")
      end
  end
end
