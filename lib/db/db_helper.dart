import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/attendance.dart';
import '../models/contact.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._();
  static Database? _database;

  DBHelper._();

  factory DBHelper() => _instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'contacts.db'),
      onCreate: (db, version) async {
        // Create contacts table
        await db.execute('''
          CREATE TABLE contacts (
            id TEXT PRIMARY KEY,
            firstName TEXT,
            middleName TEXT,
            lastName TEXT,
            grade TEXT,
            occupation TEXT,
            history TEXT
          )
        ''');

        // Create attendance table
        await db.execute('''
          CREATE TABLE attendance (
            eventId TEXT,
            eventTitle TEXT,
            eventDate TEXT,
            contacts TEXT,
            PRIMARY KEY (eventId)
          )
        ''');
      },
      version: 1,
    );
  }

  // -------------------------------------------------------------
  // ATTENDANCE METHODS
  // -------------------------------------------------------------

  /// Insert or replace an [Attendance] entry in the database.
  /// The `contacts` map is converted to JSON before insertion.
  Future<int> insertAttendance(Attendance attendance) async {
    final db = await database;

    // Convert Attendance to Map
    final attendanceMap = attendance.toMap();

    // Convert `contacts` from Map<String, int> to JSON (Sqflite only supports basic types)
    final jsonContacts = jsonEncode(attendanceMap['contacts']);
    attendanceMap['contacts'] = jsonContacts;

    return db.insert(
      'attendance',
      attendanceMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve a list of [Attendance] objects for a given eventId
  /// and decode the `contacts` JSON back into a Map<String, bool>.
  Future<List<Attendance>> getAttendanceByEvent(String eventId) async {
    final db = await database;
    final maps = await db.query(
      'attendance',
      where: 'eventId = ?',
      whereArgs: [eventId],
    );

    return maps.map((map) {
      // Decode the JSON string back into a Map
      final contactsJson = map['contacts'] as String;
      final decodedContacts = jsonDecode(contactsJson) as Map<String, dynamic>;

      // The rest of the fields are already basic strings
      return Attendance(
        eventId: map['eventId'] as String,
        eventTitle: map['eventTitle'] as String,
        eventDate: DateTime.parse(map['eventDate'] as String),
        // Convert 1/0 to bool
        contacts: decodedContacts.map(
              (key, value) => MapEntry(key, value == 1),
        ),
      );
    }).toList();
  }

  // -------------------------------------------------------------
  // CONTACTS METHODS
  // -------------------------------------------------------------

  Future<int> insertContact(Contact contact) async {
    final db = await database;

    // Convert contact to a normal Map
    final contactMap = contact.toMap();

    // Encode the List<HistoryEntry> as JSON before inserting
    contactMap['history'] = jsonEncode(contactMap['history']);

    return db.insert(
      'contacts',
      contactMap,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Contact>> getContacts() async {
    final db = await database;
    final maps = await db.query('contacts');

    print(maps);

    // Each map['history'] is still a JSON string, so decode it
    return maps.map((map) {
      // Make a copy so we can modify it safely
      final contactMap = Map<String, dynamic>.from(map);

      // Decode the JSON string back into a List of Maps
      final historyJson = contactMap['history'] as String?;
      if (historyJson != null && historyJson.isNotEmpty) {
        contactMap['history'] = jsonDecode(historyJson);
      } else {
        contactMap['history'] = [];
      }

      // Now build a Contact
      return Contact.fromMap(contactMap);
    }).toList();
  }

  Future<int> deleteContact(String id) async {
    final db = await database;
    return db.delete(
      'contacts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateContact(Contact contact) async {
    final db = await database;

    // Convert contact to Map and encode history as JSON
    final contactMap = contact.toMap();
    contactMap['history'] = jsonEncode(contactMap['history']);

    return db.update(
      'contacts',
      contactMap,
      where: 'id = ?',
      whereArgs: [contact.id],
    );
  }
}