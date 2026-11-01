### Added

- The database and uploaded files are backed up once a day (`BACKUP_SCHEDULE` changes it) to a folder or an S3-compatible bucket, with `bin/rails backup:now`, `backup:status` and `backup:restore`. With neither set, production boots and logs that backups are off: see the deployment guide's "Back up the database".
