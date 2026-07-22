import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  static GoogleDriveService? _testOverride;

  factory GoogleDriveService() => _testOverride ?? _instance;

  static const String _prefKeyHasSignedIn = 'google_has_signed_in';
  static const List<String> _scopes = [drive.DriveApi.driveFileScope];

  final GoogleSignIn _googleSignIn;

  GoogleDriveService._internal() : _googleSignIn = GoogleSignIn.instance {
    _setupUserListener();
    _initPrefs();
  }

  @visibleForTesting
  GoogleDriveService.testHarness({
    required GoogleSignIn googleSignIn,
    SharedPreferences? prefs,
  }) : _googleSignIn = googleSignIn {
    _setupUserListener();
    if (prefs != null) {
      _hasPreviouslySignedIn = prefs.getBool(_prefKeyHasSignedIn) ?? false;
      _prefsInitFuture = Future.value();
    } else {
      _initPrefs();
    }
  }

  @visibleForTesting
  static void overrideForTest(GoogleDriveService service) {
    _testOverride = service;
  }

  @visibleForTesting
  static void resetTestOverride() {
    _testOverride = null;
  }

  Future<void>? _prefsInitFuture;
  Future<void> _initPrefs() async {
    _prefsInitFuture = () async {
      final prefs = await SharedPreferences.getInstance();
      _hasPreviouslySignedIn = prefs.getBool(_prefKeyHasSignedIn) ?? false;
    }();
    return _prefsInitFuture;
  }

  final _userController = StreamController<GoogleSignInAccount?>.broadcast();
  Stream<GoogleSignInAccount?> get onUserChanged => _userController.stream;

  bool _hasAttemptedSilentSignIn = false;
  bool _isInitializing = false;
  bool _hasPreviouslySignedIn = false;
  bool _isPluginInitialized = false;

  /// Whether silent sign-in has been attempted in this session.
  bool get hasAttemptedSilentSignIn => _hasAttemptedSilentSignIn;

  /// Whether the service is currently attempting a silent sign-in.
  bool get isInitializing => _isInitializing;

  /// Whether the user has previously signed in successfully.
  bool get hasPreviouslySignedIn => _hasPreviouslySignedIn;

  Future<GoogleSignInAccount?>? _silentSignInFuture;
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _lastSignInError;

  @visibleForTesting
  void setDriveApiForTest(drive.DriveApi api) {
    _driveApi = api;
  }

  /// Returns the latest error message from a sign-in attempt.
  String? get lastSignInError => _lastSignInError;

  void _setupUserListener() {
    _googleSignIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        _currentUser = event.user;
        _userController.add(_currentUser);
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        _currentUser = null;
        _driveApi = null;
        _userController.add(null);
      }
    });
  }

  /// Initializes the Google Sign-In plugin and attempts silent sign-in.
  Future<void> initialize() async {
    if (_isPluginInitialized) return;

    // Ensure preferences are loaded first
    await (_prefsInitFuture ?? _initPrefs());

    await _googleSignIn.initialize(
      clientId: Platform.isMacOS
          ? '228185988095-9soj0hn2t78nnfbe1bt5amt54tjtnap2.apps.googleusercontent.com'
          : null,
      serverClientId: Platform.isAndroid
          ? '228185988095-ivj6ecnta0gpbr2shafll68bsqtae4t2.apps.googleusercontent.com'
          : null,
    );
    _isPluginInitialized = true;

    // Always attempt silent sign-in on initialization if we've signed in before
    if (_hasPreviouslySignedIn) {
      if (kDebugMode) {
        print('GoogleDriveService: Attempting automatic silent sign-in');
      }
      // Await silent sign-in to ensure user is available for initial app state
      await _performSilentSignIn();
    }
  }

  /// Returns the current user, attempting silent sign-in ONLY if it hasn't
  /// been attempted before in this session and the user has previously signed in.
  Future<GoogleSignInAccount?> get currentUser async {
    if (!_isPluginInitialized) {
      await initialize();
    }

    if (_currentUser != null) return _currentUser;

    // If we've already tried and failed, don't keep hammering it unless we have an active future
    if (_hasAttemptedSilentSignIn && _silentSignInFuture == null) return null;

    return await _performSilentSignIn();
  }

  Future<GoogleSignInAccount?> _performSilentSignIn() async {
    // Prevent concurrent silent sign-in attempts
    if (_silentSignInFuture != null) return _silentSignInFuture;

    _isInitializing = true;

    try {
      final future = _googleSignIn.attemptLightweightAuthentication();
      if (future == null) {
        _hasAttemptedSilentSignIn = true;
        _isInitializing = false;
        return null;
      }

      _silentSignInFuture = future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) print('Silent sign-in timed out');
          return null;
        },
      );

      final user = await _silentSignInFuture;
      _currentUser = user;

      // Update our persistent flag based on actual result
      if (user != null) {
        if (!_hasPreviouslySignedIn) {
          _hasPreviouslySignedIn = true;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_prefKeyHasSignedIn, true);
        }
      }

      return user;
    } catch (e) {
      if (kDebugMode) {
        print('Silent sign-in failed: $e');
      }
      return null;
    } finally {
      _hasAttemptedSilentSignIn = true;
      _silentSignInFuture = null;
      _isInitializing = false;
      _userController.add(_currentUser);
    }
  }

  /// explicit sign in - usually triggered by user interaction
  Future<GoogleSignInAccount?> signIn() async {
    if (!_isPluginInitialized) {
      await initialize();
    }

    _lastSignInError = null;
    try {
      // In v7.0.0, signIn is replaced by authenticate
      _currentUser = await _googleSignIn.authenticate();
      _driveApi = null;

      if (_currentUser != null) {
        _hasPreviouslySignedIn = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKeyHasSignedIn, true);
        _userController.add(_currentUser);

        // Also ensure authorization for drive scopes
        await _ensureApiInitialized(force: true);
      }

      return _currentUser;
    } catch (e) {
      String errorMessage = 'Google Sign-In failed';
      if (e.toString().contains('ApiException: 10')) {
        errorMessage =
            'Google Sign-In failed (Status 10). This usually means the SHA-1 fingerprint '
            'is not registered in the Google Cloud/Firebase console, or the package '
            'name/config is incorrect.';
      }

      _lastSignInError = errorMessage;
      if (kDebugMode) {
        print('$errorMessage: $e');
      }
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;

    _hasPreviouslySignedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyHasSignedIn, false);
    _userController.add(null);
  }

  Future<bool> isSignedIn() async {
    // Rely on cached user if available
    if (_currentUser != null) return true;

    // In v7.0.0, isSignedIn() is removed.
    // We can use attemptLightweightAuthentication() to check.
    final user = await currentUser;
    return user != null;
  }

  /// Checks if there is basic internet connectivity.
  Future<bool> _hasConnectivity() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Ensures the Drive API client is initialized.
  /// This may trigger a keychain access prompt on macOS.
  /// Silent by default; will NOT trigger interactive sign-in dialog.
  Future<void> _ensureApiInitialized({bool force = false}) async {
    if (!await _hasConnectivity()) {
      throw Exception('No internet connection');
    }

    // If already initialized and not forcing, we can do a quick check
    if (_driveApi != null && !force) {
      try {
        // Just verify we still have an authenticated user/client
        final user = await currentUser;
        if (user != null) {
          return; // Still good
        }
      } catch (_) {
        // Fall through to re-init
      }
    }

    // Silent sign-in only for background/automated tasks
    final user = await currentUser;

    if (user != null) {
      try {
        // In v7.0.0, we use authorizationClient to get authorization for scopes
        var auth = await user.authorizationClient.authorizationForScopes(
          _scopes,
        );

        if (auth == null) {
          if (force) {
            auth = await user.authorizationClient.authorizeScopes(_scopes);
          } else {
            throw Exception('Not authorized for Google Drive scopes');
          }
        }

        // Use extension authClient(scopes: ...) from extension_google_sign_in_as_googleapis_auth
        final authClient = auth.authClient(scopes: _scopes);
        _driveApi = drive.DriveApi(authClient);
      } catch (e) {
        _driveApi = null;
        if (kDebugMode) {
          print('Error getting authenticated client: $e');
        }
        throw Exception('Failed to initialize Google Drive client: $e');
      }
    } else {
      _driveApi = null;
      throw Exception('Not signed in to Google Drive (Silent sign-in failed)');
    }
  }

  /// Executes a Drive API call with a single retry if it fails due to an invalid token.
  Future<T> _executeWithRetry<T>(Future<T> Function() action) async {
    try {
      await _ensureApiInitialized();
      return await action();
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('invalid_token') ||
          errorStr.contains('401') ||
          errorStr.contains('Access was denied')) {
        if (kDebugMode) {
          print('Drive API call failed with auth error, retrying: $e');
        }
        // Force re-initialization of API client
        await _ensureApiInitialized(force: true);
        return await action();
      }
      rethrow;
    }
  }

  /// Finds a folder by name, or creates it if it doesn't exist.
  Future<String?> _getOrCreateFolder(String folderName) async {
    return await _executeWithRetry(() async {
      final query =
          "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
      final folderList = await _driveApi!.files
          .list(q: query)
          .timeout(const Duration(seconds: 10));

      if (folderList.files != null && folderList.files!.isNotEmpty) {
        return folderList.files!.first.id;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await _driveApi!.files
          .create(folder)
          .timeout(const Duration(seconds: 15));
      return createdFolder.id;
    });
  }

  Future<void> uploadFile(
    File localFile,
    String remoteName, {
    String folderName = 'BNPB-Sync',
  }) async {
    final folderId = await _getOrCreateFolder(folderName);

    await _executeWithRetry(() async {
      final query =
          "name = '$remoteName' and '$folderId' in parents and trashed = false";
      final existingFiles = await _driveApi!.files
          .list(q: query)
          .timeout(const Duration(seconds: 10));

      final driveFile = drive.File()..name = remoteName;

      final media = drive.Media(localFile.openRead(), localFile.lengthSync());

      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        // Update existing file
        await _driveApi!.files
            .update(
              driveFile,
              existingFiles.files!.first.id!,
              uploadMedia: media,
            )
            .timeout(const Duration(seconds: 30));
      } else {
        // Create new file
        if (folderId != null) {
          driveFile.parents = [folderId];
        }
        await _driveApi!.files
            .create(driveFile, uploadMedia: media)
            .timeout(const Duration(seconds: 30));
      }
    });
  }

  Future<List<drive.File>> listSyncFiles({
    String folderName = 'BNPB-Sync',
  }) async {
    final folderId = await _getOrCreateFolder(folderName);
    if (folderId == null) {
      if (kDebugMode) {
        print('listSyncFiles: folderId is null, returning empty list');
      }
      return [];
    }

    return await _executeWithRetry(() async {
      final query = "'$folderId' in parents and trashed = false";
      final allFiles = <drive.File>[];
      String? pageToken;

      do {
        final fileList = await _driveApi!.files
            .list(
              q: query,
              $fields: 'nextPageToken, files(id, name, modifiedTime, size)',
              pageSize: 1000,
              pageToken: pageToken,
            )
            .timeout(const Duration(seconds: 15));

        allFiles.addAll(fileList.files ?? []);
        pageToken = fileList.nextPageToken;
      } while (pageToken != null);

      if (kDebugMode) {
        debugPrint('listSyncFiles: Found ${allFiles.length} files in Drive');
        for (final f in allFiles) {
          debugPrint('  - ${f.name}');
        }
      }

      return allFiles;
    });
  }

  Future<void> downloadFile(String fileId, File targetFile) async {
    await _executeWithRetry(() async {
      final mediaResponse = await _driveApi!.files
          .get(fileId, downloadOptions: drive.DownloadOptions.fullMedia)
          .timeout(const Duration(seconds: 30)) as drive.Media;

      final sink = targetFile.openWrite();
      try {
        await sink.addStream(mediaResponse.stream);
      } finally {
        await sink.close();
      }
    });
  }
}
