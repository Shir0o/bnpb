import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/contact.dart';
import 'dart:convert';

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
      },
      version: 1,
    );
  }

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