# frozen_string_literal: true

class DatabaseBackup
  class Bucket
    def initialize(service = nil)
      @service = service
    end

    delegate :upload, :download, to: :service

    def prune(_prefix, keep:)
      # The bucket's lifecycle rule prunes, so the server's key needs no delete permission.
    end

    def caveat = nil

    private
      def service = @service ||= ActiveStorage::Blob.services.fetch(:object_storage)
  end
end
