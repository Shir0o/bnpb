import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:encrypt/encrypt.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/contact.dart';

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

/// Provides CSV, PDF, and encrypted archive exports for contacts.
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
      id: 'tags',
      label: 'Tags',
      description: 'Relationship and grouping tags',
    ),
    ExportField(
      id: 'contactMethods',
      label: 'Contact methods',
      description: 'Emails, phone numbers, and other reach-out channels',
    ),
    ExportField(
      id: 'recognitionKeywords',
      label: 'Recognition keywords',
      description: 'Personal cues that help remember the contact',
    ),
    ExportField(
      id: 'recognitionReminders',
      label: 'Reminders',
      description: 'Gentle prompts like birthdays or follow-ups',
    ),
    ExportField(
      id: 'firstMeetingNotes',
      label: 'First meeting notes',
      description: 'Context from the very first interaction',
    ),
  ];

  /// Generates a CSV file for the selected contacts and fields.
  Future<File> exportCsv(
    List<Contact> contacts,
    List<String> fieldIds,
  ) async {
    final rows = <List<String>>[];
    rows.add(fieldIds.map(_labelForField).toList());

    for (final contact in contacts) {
      rows.add(fieldIds.map((field) => _stringValueForField(contact, field)).toList());
    }

    final csvContent = const ListToCsvConverter().convert(rows);
    final file = await _createTempFile('contacts_export', 'csv');
    await file.writeAsString(csvContent);
    return file;
  }

  /// Generates a PDF file containing a table of the selected fields.
  Future<File> exportPdf(
    List<Contact> contacts,
    List<String> fieldIds,
  ) async {
    final pdf = pw.Document();
    final headers = fieldIds.map(_labelForField).toList();
    final data = contacts
        .map((contact) => fieldIds
            .map((field) => _stringValueForField(contact, field))
            .toList())
        .toList();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text('BNPB contact export', style: pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
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

  /// Creates an AES-encrypted ZIP archive with the selected fields as JSON.
  Future<File> exportEncryptedArchive(
    List<Contact> contacts,
    List<String> fieldIds,
    String passphrase,
  ) async {
    final payload = contacts
        .map((contact) => _jsonValueForFieldSelection(contact, fieldIds))
        .toList();

    final jsonBytes = utf8.encode(jsonEncode(payload));

    final archive = Archive()
      ..addFile(ArchiveFile('contacts.json', jsonBytes.length, jsonBytes));
    final zippedBytes = ZipEncoder().encode(archive)!;

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
      case 'tags':
        return contact.tags.join(', ');
      case 'contactMethods':
        return contact.contactMethods
            .map((method) =>
                method.label != null && method.label!.isNotEmpty
                    ? '${method.label}: ${method.value}'
                    : '${method.type}: ${method.value}')
            .join('; ');
      case 'recognitionKeywords':
        return contact.recognitionKeywords.join(', ');
      case 'recognitionReminders':
        return contact.recognitionReminders.join(', ');
      case 'firstMeetingNotes':
        return contact.firstMeetingNotes ?? '';
    }
    return '';
  }

  Map<String, dynamic> _jsonValueForFieldSelection(
    Contact contact,
    List<String> fields,
  ) {
    final map = <String, dynamic>{};
    for (final field in fields) {
      switch (field) {
        case 'firstName':
          map['firstName'] = contact.firstName;
          break;
        case 'lastName':
          map['lastName'] = contact.lastName;
          break;
        case 'nickname':
          map['nickname'] = contact.nickname;
          break;
        case 'location':
          map['location'] = contact.location;
          break;
        case 'tags':
          map['tags'] = contact.tags;
          break;
        case 'contactMethods':
          map['contactMethods'] = contact.contactMethods
              .map((method) => method.toMap())
              .toList();
          break;
        case 'recognitionKeywords':
          map['recognitionKeywords'] = contact.recognitionKeywords;
          break;
        case 'recognitionReminders':
          map['recognitionReminders'] = contact.recognitionReminders;
          break;
        case 'firstMeetingNotes':
          map['firstMeetingNotes'] = contact.firstMeetingNotes;
          break;
      }
    }
    return map;
  }

  Key _deriveKey(String passphrase) {
    final digest = sha256.convert(utf8.encode(passphrase));
    return Key(Uint8List.fromList(digest.bytes.sublist(0, 32)));
  }
}
