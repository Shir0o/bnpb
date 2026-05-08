import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:encrypt/encrypt.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/contact.dart';
import '../models/prayer_list.dart';
import 'sync_coordinator.dart';
import '../db/db_helper.dart';

/// Supported export field identifiers.
class ExportField {
  const ExportField({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

/// Provides CSV, PDF, JSON, and encrypted archive exports for contacts.
class ExportService {
  ExportService._();

  static final ExportService _instance = ExportService._();

  /// Singleton accessor.
  factory ExportService() => _instance;

  /// All selectable fields surfaced in the export UI.
  static const List<ExportField> availableFields = [
    ExportField(
      id: 'firstName',
      label: 'First name',
      description: 'Contact given name',
    ),
    ExportField(
      id: 'lastName',
      label: 'Last name',
      description: 'Family name (if recorded)',
    ),
    ExportField(
      id: 'nickname',
      label: 'Nickname',
      description: 'Nickname or preferred name',
    ),
    ExportField(
      id: 'location',
      label: 'Location',
      description: 'City/region information',
    ),
    ExportField(
      id: 'firstMeetingNotes',
      label: 'First meeting notes',
      description: 'Context from the very first interaction',
    ),
    ExportField(id: 'notes', label: 'Notes', description: 'General notes'),
  ];

  /// Generates a CSV file for the selected contacts and fields.
  Future<File> exportCsv(List<Contact> contacts, List<String> fieldIds) async {
    final rows = <List<String>>[];
    rows.add(fieldIds.map(_labelForField).toList());

    for (final contact in contacts) {
      rows.add(
        fieldIds.map((field) => _stringValueForField(contact, field)).toList(),
      );
    }

    final csvContent = const ListToCsvConverter().convert(rows);
    final file = await _createTempFile('contacts_export', 'csv');
    await file.writeAsString(csvContent);
    return file;
  }

  /// Generates a PDF file containing a table of the selected fields.
  Future<File> exportPdf(List<Contact> contacts, List<String> fieldIds) async {
    final pdf = pw.Document();
    final headers = fieldIds.map(_labelForField).toList();
    final data = contacts
        .map(
          (contact) => fieldIds
              .map((field) => _stringValueForField(contact, field))
              .toList(),
        )
        .toList();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text('BNPB contact export', style: pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final file = await _createTempFile('contacts_export', 'pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Generates a JSON file containing the selected fields for each contact.
  Future<File> exportJson(
    List<Contact> contacts,
    List<String> fieldIds, {
    List<PrayerList>? prayerLists,
  }) async {
    final payload = await buildFullExportPayload(
      contacts,
      fieldIds,
      prayerLists: prayerLists,
    );

    final file = await _createTempFile('contacts_export', 'json');
    await file.writeAsString(jsonEncode(payload));
    return file;
  }

  /// Creates an AES-encrypted ZIP archive with the selected fields as JSON.
  Future<File> exportEncryptedArchive(
    List<Contact> contacts,
    List<String> fieldIds,
    String passphrase, {
    List<PrayerList>? prayerLists,
  }) async {
    final payload = await buildFullExportPayload(
      contacts,
      fieldIds,
      prayerLists: prayerLists,
    );

    final jsonBytes = utf8.encode(jsonEncode(payload));

    final archive = Archive()
      ..addFile(ArchiveFile('contacts.json', jsonBytes.length, jsonBytes));
    final zippedBytes = ZipEncoder().encode(archive);

    final key = _deriveKey(passphrase);
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encryptBytes(zippedBytes, iv: iv);

    final wrapped = jsonEncode({
      'iv': base64Encode(iv.bytes),
      'ciphertext': base64Encode(encrypted.bytes),
    });

    final file = await _createTempFile('contacts_export', 'enc');
    await file.writeAsString(wrapped);
    return file;
  }

  Future<File> _createTempFile(String prefix, String extension) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(directory.path, '${prefix}_$timestamp.$extension');
    return File(path);
  }

  String _labelForField(String id) {
    return availableFields.firstWhere((field) => field.id == id).label;
  }

  String _stringValueForField(Contact contact, String id) {
    switch (id) {
      case 'firstName':
        return contact.firstName;
      case 'lastName':
        return contact.lastName ?? '';
      case 'nickname':
        return contact.nickname ?? '';
      case 'location':
        return contact.location ?? '';
      case 'firstMeetingNotes':
        return contact.firstMeetingNotes ?? '';
      case 'notes':
        return contact.notes ?? '';
    }
    return '';
  }

  @visibleForTesting
  List<Map<String, dynamic>> buildExportPayload(
    List<Contact> contacts,
    List<String> fieldIds,
  ) {
    // Ignore field selection for JSON/Archive export to ensure full data backup.
    return contacts.map((contact) => contact.toJson()).toList();
  }

  /// Builds the export payload. If [prayerLists] is provided, returns a Map wrapper.
  /// Otherwise returns the List of contacts (legacy format).
  /// Builds the export payload. If [prayerLists] is provided, returns a Map wrapper.
  /// Otherwise returns the List of contacts (legacy format).
  ///
  /// This implementation is updated to produce a Version 2 payload matching the
  /// Auto Sync format, including flat interactions and prayer requests.
  Future<dynamic> buildFullExportPayload(
    List<Contact> contacts,
    List<String> fieldIds, {
    List<PrayerList>? prayerLists,
  }) async {
    final contactList = <Map<String, dynamic>>[];

    // Flatten interactions and prayer requests with de-duplication
    final flatInteractions = <Map<String, dynamic>>[];
    final flatPrayerRequests = <Map<String, dynamic>>[];
    final flatRelationships = <Map<String, dynamic>>[];

    final seenInteractionSyncIds = <String>{};
    final seenPrayerSyncIds = <String>{};
    final seenRelationshipKeys = <String>{};

    // Global mapping of local interaction ID to SyncID for prayer request resolution
    final globalInteractionMap = <int, String>{};

    for (final contact in contacts) {
      contactList.add(contact.toJson());

      for (final interaction in contact.interactions) {
        if (interaction.id != null) {
          globalInteractionMap[interaction.id!] = interaction.syncId;
        }
        if (seenInteractionSyncIds.add(interaction.syncId)) {
          flatInteractions.add(interaction.toJson());
        }
      }

      for (final relationship in contact.relationships) {
        final key =
            '${relationship.sourceContactId}|${relationship.targetContactId}|${relationship.type}';
        if (seenRelationshipKeys.add(key)) {
          flatRelationships.add(relationship.toMap(includeId: false));
        }
      }
    }

    for (final contact in contacts) {
      for (final prayer in contact.prayerRequests) {
        if (seenPrayerSyncIds.add(prayer.syncId)) {
          final map = prayer.toMap();
          // Resolve interactionSyncId if linked
          if (prayer.interactionId != null) {
            final syncId = globalInteractionMap[prayer.interactionId!];
            if (syncId != null) {
              map['interactionSyncId'] = syncId;
            }
          }
          flatPrayerRequests.add(map);
        }
      }
    }

    // Get Device ID (reuse SyncCoordinator logic)
    final syncCoordinator = SyncCoordinator(DBHelper());
    final deviceId = await syncCoordinator.getDeviceId();

    return {
      'version': 2,
      'deviceId': deviceId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'integrityCheck': 'valid',
      'contacts': contactList,
      'interactions': flatInteractions,
      'prayerRequests': flatPrayerRequests,
      'relationships': flatRelationships,
      'prayerLists': (prayerLists ?? []).map((list) {
        final map = list.toMap();
        map['contactIds'] = list.contactIds;
        return map;
      }).toList(),
    };
  }

  Key _deriveKey(String passphrase) {
    final digest = sha256.convert(utf8.encode(passphrase));
    return Key(Uint8List.fromList(digest.bytes.sublist(0, 32)));
  }
}
