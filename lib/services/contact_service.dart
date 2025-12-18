import 'package:flutter/foundation.dart';
import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';

class ContactService {
  static final ContactService _instance = ContactService._internal();
  factory ContactService() => _instance;
  ContactService._internal();

  final DBHelper _dbHelper = DBHelper();
  
  List<Contact>? _cachedContacts;
  final Map<String, List<Interaction>> _cachedInteractions = {};

  bool get hasCachedContacts => _cachedContacts != null;
  bool hasCachedInteractions(String contactId) => _cachedInteractions.containsKey(contactId);

  /// Returns cached contacts if available, otherwise fetches them.
  /// [forceRefresh] will ignore cache and fetch fresh data.
  Future<List<Contact>> getContacts({bool forceRefresh = false}) async {
    if (_cachedContacts != null && !forceRefresh) {
      return _cachedContacts!;
    }
    
    final contacts = await _dbHelper.getContacts();
    _cachedContacts = contacts;
    return contacts;
  }

  /// Returns cached interactions for a contact if available, otherwise fetches them.
  /// [forceRefresh] will ignore cache and fetch fresh data.
  Future<List<Interaction>> getInteractions(String contactId, {bool forceRefresh = false}) async {
    if (_cachedInteractions.containsKey(contactId) && !forceRefresh) {
      return _cachedInteractions[contactId]!;
    }

    final interactions = await _dbHelper.getInteractionsForContact(contactId);
    _cachedInteractions[contactId] = interactions;
    return interactions;
  }

  void clearCache() {
    _cachedContacts = null;
    _cachedInteractions.clear();
  }

  void invalidateContacts() {
    _cachedContacts = null;
  }

  void invalidateInteractions(String contactId) {
    _cachedInteractions.remove(contactId);
  }
}
