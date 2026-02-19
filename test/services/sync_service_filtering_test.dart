import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Sync Service Logic', () {
    test('should filter out processed files and own files', () {
      final deviceId = 'device_123';
      final processedFiles = {'other_processed_1.json'};

      final remoteFiles = [
        'device_123_1000.json', // Own file -> Skip
        'other_processed_1.json', // Processed -> Skip
        'other_new_2.json', // New -> Download
      ];

      final toDownload = remoteFiles.where((name) {
        // Logic from SyncService._performGoogleSync
        if (processedFiles.contains(name)) return false;
        if (name.startsWith(deviceId)) return false;
        return true;
      }).toList();

      expect(toDownload, ['other_new_2.json']);
    });
  });
}
