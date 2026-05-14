import 'package:bnpb/services/ai/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelManager.ensureFreeSpace', () {
    test('passes when probe reports ample free space', () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => 10000,
      );
      await manager.ensureFreeSpace(path: '/tmp');
    });

    test('throws InsufficientStorageException when probe reports too little',
        () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => 500,
      );
      await expectLater(
        manager.ensureFreeSpace(path: '/tmp'),
        throwsA(isA<InsufficientStorageException>()),
      );
    });

    test('passes (no-op) when probe returns null (unknown free space)',
        () async {
      final manager = ModelManager(
        requiredFreeBytes: 1000,
        freeSpaceProbe: (_) async => null,
      );
      await manager.ensureFreeSpace(path: '/tmp');
    });

    test('InsufficientStorageException.toString surfaces a friendly message',
        () {
      final e = InsufficientStorageException(
        requiredBytes: 3500 * 1024 * 1024,
        freeBytes: 1024 * 1024 * 1024,
      );
      final msg = e.toString();
      expect(msg, contains('3.4 GB'));
      expect(msg, contains('1.0 GB'));
      expect(msg, contains('free some space'));
    });
  });
}
