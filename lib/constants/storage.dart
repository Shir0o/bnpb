/// Storage-related constants shared across the application.
class StorageConstants {
  /// File name used for the encrypted SQLite database on disk.
  static const String databaseFileName = 'contacts.db';

  /// Directory within the application documents folder used for rolling backups.
  static const String backupDirectory = 'backups';
}
