import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnpb/models/candidate_interaction.dart';
import 'package:bnpb/models/contact.dart';
import 'package:bnpb/models/interaction.dart';
import 'package:bnpb/services/candidate_collision_detector.dart';
import 'package:bnpb/services/google_drive_service.dart';
import 'package:bnpb/services/time_tracker_parser.dart';

/// Service managing background check, download, parsing, and staging of Simple
/// Time Tracker CSV records from Google Drive.
class TimeTrackerSyncService extends ChangeNotifier {
  static const String _prefKeyImportedFingerprints =
      'stt_imported_fingerprints';
  static const String _prefKeyStagedCandidates = 'stt_staged_candidates';
  static const String _prefKeyDriveFolder = 'stt_drive_folder_name';
  static const String _prefKeyNameMarkers = 'stt_name_markers';
  static const String defaultDriveFolderName = 'Time track';
  static const List<String> defaultNameMarkers = ['w/', 'with '];

  final GoogleDriveService _driveService;
  List<CandidateInteraction> _stagingQueue = [];
  bool _isSyncing = false;

  /// Creates a [TimeTrackerSyncService].
  TimeTrackerSyncService({
    GoogleDriveService? driveService,
  }) : _driveService = driveService ?? GoogleDriveService() {
    _loadStagedCandidates();
  }

  /// The list of candidate interactions currently staged for review.
  List<CandidateInteraction> get stagingQueue =>
      List.unmodifiable(_stagingQueue);

  /// Whether a sync operation is currently active.
  bool get isSyncing => _isSyncing;

  /// Whether there are candidate interactions pending review.
  bool get hasStagedCandidates => _stagingQueue.isNotEmpty;

  Future<void> _loadStagedCandidates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKeyStagedCandidates);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _stagingQueue = list
            .map((item) =>
                CandidateInteraction.fromJson(item as Map<String, dynamic>))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading staged candidates: $e');
    }
  }

  Future<void> _saveStagedCandidates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_stagingQueue.map((e) => e.toJson()).toList());
      await prefs.setString(_prefKeyStagedCandidates, jsonStr);
    } catch (e) {
      debugPrint('Error saving staged candidates: $e');
    }
  }

  /// Retrieves the set of record fingerprints that have already been imported.
  Future<Set<String>> getImportedFingerprints() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKeyImportedFingerprints) ?? [];
    return list.toSet();
  }

  /// Marks [fingerprints] as imported in persistent storage and removes them from staging.
  Future<void> markImported(Iterable<String> fingerprints) async {
    final prefs = await SharedPreferences.getInstance();
    final current =
        (prefs.getStringList(_prefKeyImportedFingerprints) ?? []).toSet();
    current.addAll(fingerprints);
    await prefs.setStringList(_prefKeyImportedFingerprints, current.toList());

    // Also remove from staging queue
    removeCandidates(fingerprints);
  }

  /// Replaces the current staging queue with [candidates].
  void setStagingQueue(List<CandidateInteraction> candidates) {
    _stagingQueue = List.from(candidates);
    _saveStagedCandidates();
    notifyListeners();
  }

  /// Updates an existing candidate in the staging queue.
  void updateCandidate(CandidateInteraction candidate) {
    final idx =
        _stagingQueue.indexWhere((e) => e.fingerprint == candidate.fingerprint);
    if (idx != -1) {
      _stagingQueue[idx] = candidate;
      _saveStagedCandidates();
      notifyListeners();
    }
  }

  /// Removes candidates matching [fingerprints] from the staging queue.
  void removeCandidates(Iterable<String> fingerprints) {
    final fpSet = fingerprints.toSet();
    _stagingQueue.removeWhere((e) => fpSet.contains(e.fingerprint));
    _saveStagedCandidates();
    notifyListeners();
  }

  /// Clears all candidates from the staging queue.
  void clearStagingQueue() {
    _stagingQueue.clear();
    _saveStagedCandidates();
    notifyListeners();
  }

  /// Returns the configured Google Drive folder name, defaulting to [defaultDriveFolderName].
  Future<String> getDriveFolderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyDriveFolder) ?? defaultDriveFolderName;
  }

  /// Sets the configured Google Drive folder name.
  Future<void> setDriveFolderName(String folderName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDriveFolder, folderName.trim());
    notifyListeners();
  }

  /// Returns the configured name markers, defaulting to [defaultNameMarkers].
  Future<List<String>> getNameMarkers() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKeyNameMarkers);
    if (stored == null || stored.isEmpty) return List.of(defaultNameMarkers);
    return stored
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Sets the configured name markers from a comma-separated string.
  Future<void> setNameMarkers(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyNameMarkers, value.trim());
    notifyListeners();
  }

  /// Queries Google Drive for the newest `stt_records_automatic*.csv` in the
  /// configured folder (or [folderName]), parses rows tagged with "Contact",
  /// filters already imported items, checks collisions against [existingInteractions],
  /// and populates the staging queue.
  Future<List<CandidateInteraction>> syncFromDrive({
    required List<Contact> contacts,
    List<Interaction>? existingInteractions,
    String? folderName,
  }) async {
    _isSyncing = true;
    notifyListeners();

    try {
      final targetFolder = folderName ?? await getDriveFolderName();
      final latestFile = await _driveService.findLatestFileInFolder(
        folderName: targetFolder,
        namePrefix: 'stt_records_automatic',
      );

      if (latestFile == null || latestFile.id == null) {
        _isSyncing = false;
        notifyListeners();
        return _stagingQueue;
      }

      final csvContent =
          await _driveService.downloadFileAsString(latestFile.id!);
      final markers = await getNameMarkers();
      final parsedCandidates = TimeTrackerParser.parseCsv(
        csvContent,
        contacts: contacts,
        markers: markers,
      );

      final importedFps = await getImportedFingerprints();

      // Only retain candidates that have not yet been imported
      var newCandidates = parsedCandidates
          .where((c) => !importedFps.contains(c.fingerprint))
          .toList();

      if (existingInteractions != null && existingInteractions.isNotEmpty) {
        newCandidates = CandidateCollisionDetector.detectCollisions(
          candidates: newCandidates,
          existingInteractions: existingInteractions,
        );
      }

      setStagingQueue(newCandidates);
      return _stagingQueue;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Commits confirmed [CandidateInteraction]s to the database and marks their fingerprints as imported.
  Future<void> commitCandidates(
    List<CandidateInteraction> candidates, {
    required Future<void> Function(Interaction interaction) saveInteraction,
  }) async {
    for (final candidate in candidates) {
      final interaction = candidate.toInteraction();
      await saveInteraction(interaction);
    }
    await markImported(candidates.map((c) => c.fingerprint));
  }
}
