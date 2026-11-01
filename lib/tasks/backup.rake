namespace :backup do
  desc "Back up the database and uploaded files now, to BACKUP_PATH or the bucket"
  task now: :environment do
    destination = DatabaseBackup.destination or abort DatabaseBackup::OFF
    puts "Backed up to #{DatabaseBackup.new(destination: destination).take!}"
  end

  desc "Name the latest backup"
  task status: :environment do
    destination = DatabaseBackup.destination or next puts(DatabaseBackup::OFF)
    latest = DatabaseBackup.new(destination: destination).latest
    puts latest ? "Latest: #{latest}" : "No backup yet."
    puts destination.caveat if destination.caveat
  end

  desc "Replace the database with the latest backup, or backup:restore[KEY], and bring back missing uploads; stop the app first"
  task :restore, [ :key ] => :environment do |_task, args|
    destination = DatabaseBackup.destination or abort DatabaseBackup::OFF
    set_aside = DatabaseBackup.new(destination: destination).restore!(args[:key])
    puts "Restored. The database it replaced is at #{set_aside}."
  end
end
