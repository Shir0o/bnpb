import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/services/time_tracker_parser.dart';

void main() {
  group('TimeTrackerParser', () {
    final contacts = [
      Contact(id: 'c1', firstName: 'Abel', lastName: 'Smith'),
      Contact(id: 'c2', firstName: 'Benji', lastName: 'Lee'),
      Contact(id: 'c3', firstName: 'Jeremy', lastName: 'Tan'),
      Contact(id: 'c4', firstName: 'Timothy', lastName: 'Wang'),
      Contact(id: 'c5', firstName: 'Isai', lastName: 'G'),
      Contact(id: 'c6', firstName: 'Edgar', lastName: 'Flores'),
      Contact(id: 'c7', firstName: 'Matthew', lastName: 'V'),
      Contact(id: 'c8', firstName: 'Fernando', lastName: 'Perez'),
    ];

    test('ignores records without Contact tag', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Coding",2025-01-07 12:07:24,2025-01-07 13:41:07,"","Productivity ","",1:33:43,93
"Commute",2025-01-07 13:41:07,2025-01-07 14:00:16,"","Transportation ","",0:19:9,19
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates, isEmpty);
    });

    test('parses record with "w/ Name" and links contact', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Lunch",2025-09-17 11:46:37,2025-09-17 12:46:37,"w/ Abel","Essentials","Contact",1:0:0,60
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.length, 1);
      final candidate = candidates.first;
      expect(candidate.activityName, 'Lunch');
      expect(candidate.occurredAt, DateTime.parse('2025-09-17 11:46:37'));
      expect(candidate.durationMinutes, 60);
      expect(candidate.matchedContactIds, ['c1']);
      expect(candidate.summary, 'Lunch w/ Abel');
      expect(candidate.rawComment, 'w/ Abel');
    });

    test('parses multiple contacts from "Boba w/ Benji Jeremy Timothy Isai"',
        () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Dinner",2025-09-19 22:16:46,2025-09-19 23:03:36,"Boba w/ Benji Jeremy Timothy Isai ","Essentials","Contact",0:46:50,46
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.length, 1);
      final candidate = candidates.first;
      expect(candidate.activityName, 'Dinner');
      expect(candidate.durationMinutes, 46);
      expect(
          candidate.matchedContactIds, containsAll(['c2', 'c3', 'c4', 'c5']));
      expect(candidate.summary, 'Dinner - Boba');
    });

    test('parses direct contact name without "w/" prefix (e.g. "Edgar Flores")',
        () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Appointment",2025-09-16 13:30:54,2025-09-16 14:30:54,"Edgar Flores ","Spiritual","Contact",1:0:0,60
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.length, 1);
      final candidate = candidates.first;
      expect(candidate.matchedContactIds, ['c6']);
      expect(candidate.summary, 'Appointment - Edgar Flores');
    });

    test(
        'parses known contact name with extra activity description (e.g. "Matthew V piano")',
        () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Appointment",2025-09-16 18:25:58,2025-09-16 19:25:58,"Matthew V piano","Productivity ","Contact",1:0:0,60
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.length, 1);
      final candidate = candidates.first;
      expect(candidate.matchedContactIds, ['c7']);
      expect(candidate.summary, 'Appointment - piano');
    });

    test('computes deterministic fingerprint for deduplication', () {
      const csvData1 = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Lunch",2025-09-17 11:46:37,2025-09-17 12:46:37,"w/ Abel","Essentials","Contact",1:0:0,60
''';
      final candidates1 =
          TimeTrackerParser.parseCsv(csvData1, contacts: contacts);
      final candidates2 =
          TimeTrackerParser.parseCsv(csvData1, contacts: contacts);

      expect(candidates1.first.fingerprint, isNotEmpty);
      expect(
          candidates1.first.fingerprint, equals(candidates2.first.fingerprint));
    });

    test('defaults to unselected when no contact is matched', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Call",2025-09-20 10:00:00,2025-09-20 10:15:00,"General chit-chat","Essentials","Contact",0:15:0,15
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.length, 1);
      expect(candidates.first.matchedContactIds, isEmpty);
      expect(candidates.first.selected, isFalse);
    });

    test('defaults to selected when a contact is matched', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Lunch",2025-09-17 11:46:37,2025-09-17 12:46:37,"w/ Abel","Essentials","Contact",1:0:0,60
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.first.selected, isTrue);
    });

    test('respects custom markers', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Coffee",2025-09-18 09:00:00,2025-09-18 09:30:00,"@ Abel","Essentials","Contact",0:30:0,30
''';

      final candidates = TimeTrackerParser.parseCsv(
        csvData,
        contacts: contacts,
        markers: ['@'],
      );
      expect(candidates.first.matchedContactIds, ['c1']);
    });

    test('does not match a bare first name without a marker', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Meeting",2025-09-21 14:00:00,2025-09-21 14:30:00,"met Abel casually","Essentials","Contact",0:30:0,30
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      // "Abel" alone is treated as ambiguous in the strict whole-comment scan.
      expect(candidates.first.matchedContactIds, isEmpty);
    });

    test('strict scan matches a full name in the whole comment', () {
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Meeting",2025-09-21 14:00:00,2025-09-21 14:30:00,"met Abel Smith casually","Essentials","Contact",0:30:0,30
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.first.matchedContactIds, ['c1']);
      expect(candidates.first.summary, 'Meeting - casually');
    });

    test('marker-respected first: names only after the marker', () {
      // "Boba" is not a contact, but even if it were, only the names after
      // "w/" should count.
      const csvData = '''
activity name,time started,time ended,comment,categories,record tags,duration,duration minutes
"Dinner",2025-09-19 22:16:46,2025-09-19 23:03:36,"Boba w/ Abel","Essentials","Contact",0:46:50,46
''';

      final candidates =
          TimeTrackerParser.parseCsv(csvData, contacts: contacts);
      expect(candidates.first.matchedContactIds, ['c1']);
      expect(candidates.first.summary, 'Dinner - Boba');
    });
  });
}
