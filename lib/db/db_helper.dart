import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/contact.dart';
import 'dart:convert'; // Required for JSON encoding and decoding

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
    return db.insert(
      'contacts',
      contact.toMap()
        ..['history'] = jsonEncode(contact.history.map((e) => e.toMap()).toList()), // Encode history as JSON
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Contact>> getContacts() async {
    final db = await database;
    final maps = await db.query('contacts');

    return maps.map((map) {
      return Contact.fromMap({
        ...map,
        'history': (jsonDecode(map['history'] as String) as List<dynamic>)
            .map((entry) => HistoryEntry.fromMap(entry))
            .toList(),
      });
    }).toList();
  }

  Future<int> deleteContact(String id) async {
    final db = await database;
    return db.delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateContact(Contact contact) async {
    final db = await database;
    return db.update(
      'contacts',
      contact.toMap()
        ..['history'] = jsonEncode(contact.history.map((e) => e.toMap()).toList()), // Encode history as JSON
      where: 'id = ?',
      whereArgs: [contact.id],
    );
  }
}