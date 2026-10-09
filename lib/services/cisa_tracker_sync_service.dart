import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';

enum CisaSyncStatus {
  noToken,
  success,
  unauthorized,
  error,
}

class CisaSyncResult {
  final CisaSyncStatus status;
  final int pushedCount;
  final String? errorMessage;

  const CisaSyncResult({
    required this.status,
    this.pushedCount = 0,
    this.errorMessage,
  });
}

class CisaTrackerSyncService {
  static final CisaTrackerSyncService _instance =
      CisaTrackerSyncService._internal();
  factory CisaTrackerSyncService({
    DBHelper? dbHelper,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  }) {
    if (dbHelper != null || secureStorage != null || httpClient != null) {
      return CisaTrackerSyncService._internal(
        dbHelper: dbHelper,
        secureStorage: secureStorage,
        httpClient: httpClient,
      );
    }
    return _instance;
  }

  CisaTrackerSyncService._internal({
    DBHelper? dbHelper,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _dbHelper = dbHelper ?? DBHelper(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client();

  static const String defaultTrackerHost = 'cisa-campus-work-tracker.pages.dev';
  static const int perRequestCap = 200;

  static const String _secureTokenKey = 'cisa_tracker_personal_sync_token';
  static const String _prefHostKey = 'cisa_tracker_host';
  static const String _prefCursorKey = 'cisa_tracker_last_push_cursor';
  static const String _prefLastSuccessKey = 'cisa_tracker_last_push_success';
  static const String _prefLastErrorKey = 'cisa_tracker_last_push_error';

  final DBHelper _dbHelper;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;

  bool _isSyncing = false;

  Future<String?> getToken() => _secureStorage.read(key: _secureTokenKey);

  Future<void> setToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clearToken();
    } else {
      await _secureStorage.write(key: _secureTokenKey, value: trimmed);
    }
  }

  Future<void> clearToken() async {
    await _secureStorage.delete(key: _secureTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefCursorKey);
    await prefs.remove(_prefLastSuccessKey);
    await prefs.remove(_prefLastErrorKey);
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<String> getTrackerHost() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefHostKey) ?? defaultTrackerHost;
  }

  Future<void> setTrackerHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = host.trim();
    if (trimmed.isEmpty || trimmed == defaultTrackerHost) {
      await prefs.remove(_prefHostKey);
    } else {
      await prefs.setString(_prefHostKey, trimmed);
    }
  }

  Future<DateTime?> getLastPushCursor() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefCursorKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<DateTime?> getLastPushSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefLastSuccessKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<String?> getLastPushError() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastErrorKey);
  }

  /// Pushes changed interactions to CISA Tracker.
  Future<CisaSyncResult> pushInteractions() async {
    if (_isSyncing) {
      return const CisaSyncResult(
        status: CisaSyncStatus.error,
        errorMessage: 'Sync already in progress',
      );
    }

    final token = await getToken();
    if (token == null || token.isEmpty) {
      return const CisaSyncResult(status: CisaSyncStatus.noToken);
    }

    _isSyncing = true;
    try {
      final host = await getTrackerHost();
      final cursor = await getLastPushCursor();

      // Retrieve interactions changed since cursor
      final interactions = await _dbHelper.getInteractions(
        updatedSince: cursor,
        includeDeleted: true,
      );

      // We sort ascending by updatedAt so that paging advances the cursor chronologically
      interactions.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

      if (interactions.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefLastSuccessKey,
          DateTime.now().toUtc().toIso8601String(),
        );
        await prefs.remove(_prefLastErrorKey);
        return const CisaSyncResult(
            status: CisaSyncStatus.success, pushedCount: 0);
      }

      // Collect all participant contacts needed for names
      final allContactIds = <String>{};
      for (final i in interactions) {
        allContactIds.addAll(i.participantIds);
      }

      final Map<String, Contact> contactsMap = {};
      if (allContactIds.isNotEmpty) {
        final contacts = await _dbHelper.getContacts(
          contactIds: allContactIds.toList(),
          includeDeleted: true,
        );
        for (final c in contacts) {
          contactsMap[c.id] = c;
        }
      }

      // Clean host to build Uri
      var cleanHost = host;
      if (cleanHost.startsWith('https://')) {
        cleanHost = cleanHost.substring(8);
      } else if (cleanHost.startsWith('http://')) {
        cleanHost = cleanHost.substring(7);
      }
      if (cleanHost.endsWith('/')) {
        cleanHost = cleanHost.substring(0, cleanHost.length - 1);
      }

      final uri = Uri.https(cleanHost, '/api/bnpb/sync');
      final prefs = await SharedPreferences.getInstance();

      int totalPushed = 0;

      // Send in pages no larger than perRequestCap
      for (int i = 0; i < interactions.length; i += perRequestCap) {
        final end = (i + perRequestCap < interactions.length)
            ? i + perRequestCap
            : interactions.length;
        final page = interactions.sublist(i, end);

        final payloadInteractions = page.map((interaction) {
          final participants = interaction.participantIds.map((cid) {
            final contact = contactsMap[cid];
            final partMap = <String, dynamic>{'bnpbContactId': cid};
            if (contact != null) {
              if (contact.firstName.trim().isNotEmpty) {
                partMap['firstName'] = contact.firstName.trim();
              }
              final lastName = contact.lastName?.trim();
              if (lastName != null && lastName.isNotEmpty) {
                partMap['lastName'] = lastName;
              }
              final nickname = contact.nickname?.trim();
              if (nickname != null && nickname.isNotEmpty) {
                partMap['nickname'] = nickname;
              }
            }
            return partMap;
          }).toList();

          final item = <String, dynamic>{
            'syncId': interaction.syncId,
            'occurredAt': interaction.occurredAt.toUtc().toIso8601String(),
            'summary': interaction.summary,
            'medium': interaction.medium,
            'updatedAt': interaction.updatedAt.toUtc().toIso8601String(),
            'deleted': interaction.deletedAt != null,
            'participants': participants,
          };

          if (interaction.durationMinutes != null) {
            item['durationMinutes'] = interaction.durationMinutes;
          }

          return item;
        }).toList();

        final response = await _httpClient.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-sync-token': token,
          },
          body: jsonEncode({'interactions': payloadInteractions}),
        );

        if (response.statusCode == 200) {
          // Advance cursor to newest updatedAt of this page
          final pageNewest = page.last.updatedAt.toUtc();
          await prefs.setString(_prefCursorKey, pageNewest.toIso8601String());
          await prefs.setString(
            _prefLastSuccessKey,
            DateTime.now().toUtc().toIso8601String(),
          );
          await prefs.remove(_prefLastErrorKey);
          totalPushed += page.length;
        } else if (response.statusCode == 401) {
          String errMsg = 'Invalid or revoked token (401).';
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['error'] != null) {
              errMsg = decoded['error'].toString();
            }
          } catch (_) {}
          await prefs.setString(_prefLastErrorKey, errMsg);
          return CisaSyncResult(
            status: CisaSyncStatus.unauthorized,
            pushedCount: totalPushed,
            errorMessage: errMsg,
          );
        } else {
          String errMsg = 'Sync failed with HTTP ${response.statusCode}';
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map && decoded['error'] != null) {
              errMsg = decoded['error'].toString();
            }
          } catch (_) {}
          await prefs.setString(_prefLastErrorKey, errMsg);
          return CisaSyncResult(
            status: CisaSyncStatus.error,
            pushedCount: totalPushed,
            errorMessage: errMsg,
          );
        }
      }

      return CisaSyncResult(
        status: CisaSyncStatus.success,
        pushedCount: totalPushed,
      );
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastErrorKey, errMsg);
      return CisaSyncResult(
        status: CisaSyncStatus.error,
        errorMessage: errMsg,
      );
    } finally {
      _isSyncing = false;
    }
  }
}
