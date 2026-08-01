import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/prayer_list.dart';
import 'package:bnpb/services/export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Prayer List Backup Tests', () {
    test('buildFullExportPayload includes provided prayer lists', () async {
      final contact = Contact(id: 'c1', firstName: 'Alice');
      final prayerList = PrayerList(
        id: 'l1',
        name: 'My Prayer List',
        contactIds: ['c1'],
      );

      final payload = await ExportService().buildFullExportPayload(
        [contact],
        ['firstName'],
        prayerLists: [prayerList],
      );

      expect(payload['prayerLists'], isNotNull);
      expect(payload['prayerLists'], hasLength(1));
      final listJson = (payload['prayerLists'] as List).first;
      expect(listJson['id'], 'l1');
      expect(listJson['name'], 'My Prayer List');
      expect(listJson['contactIds'], ['c1']);
    });
  });
}
