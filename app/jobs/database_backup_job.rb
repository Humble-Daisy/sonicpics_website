# frozen_string_literal: true

class DatabaseBackupJob < ApplicationJob
  queue_as :default

  def perform
    destination = DatabaseBackup.destination or return logger.warn(DatabaseBackup::OFF)

    DatabaseBackup.new(destination: destination).take!
    logger.warn(destination.caveat) if destination.caveat
  end
end
