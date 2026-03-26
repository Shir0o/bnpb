import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: Platform.isMacOS
        ? '228185988095-9soj0hn2t78nnfbe1bt5amt54tjtnap2.apps.googleusercontent.com'
        : null,
    serverClientId: Platform.isAndroid
        ? '228185988095-ivj6ecnta0gpbr2shafll68bsqtae4t2.apps.googleusercontent.com'
        : null,
    scopes: [drive.DriveApi.driveFileScope],
  );

  GoogleDriveService._internal() {
    _onUserChanged = _googleSignIn.onCurrentUserChanged;
    _onUserChanged.listen((account) {
      _currentUser = account;
      if (account == null) {
        _driveApi = null;
      }
    });
    // Trigger the silent sign-in automatically so it's ready when needed.
    _performSilentSignIn();
  }

  late final Stream<GoogleSignInAccount?> _onUserChanged;
  bool _hasAttemptedSilentSignIn = false;

  /// Whether silent sign-in has been attempted in this session.
  bool get hasAttemptedSilentSignIn => _hasAttemptedSilentSignIn;

  Future<GoogleSignInAccount?>? _silentSignInFuture;
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _lastSignInError;

  /// Returns the latest error message from a sign-in attempt.
  String? get lastSignInError => _lastSignInError;

  /// Stream of Google user state changes.
  Stream<GoogleSignInAccount?> get onUserChanged => _onUserChanged;

  /// Returns the current user, attempting silent sign-in ONLY if it hasn't
  /// been attempted before in this session.
  /// Does NOT initialize the Drive API client to avoid unnecessary keychain access.
  Future<GoogleSignInAccount?> get currentUser async {
    if (_currentUser != null) return _currentUser;

    // If we already tried and it failed, we don't automatically try again
    // unless the app caller forces it by calling _performSilentSignIn directly.
    if (_hasAttemptedSilentSignIn && _silentSignInFuture == null) return null;

    return await _performSilentSignIn();
  }

  Future<GoogleSignInAccount?> _performSilentSignIn() async {
    // Prevent concurrent silent sign-in attempts
    if (_silentSignInFuture != null) return _silentSignInFuture;

    _silentSignInFuture = _googleSignIn.signInSilently().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );

    try {
      final user = await _silentSignInFuture;
      _currentUser = user;
      return user;
    } catch (e) {
      if (kDebugMode) {
        print('Silent sign-in failed/timed out: $e');
      }
      return null;
    } finally {
      _hasAttemptedSilentSignIn = true;
      _silentSignInFuture = null;
    }
  }

  /// explicit sign in - usually triggered by user interaction
  Future<GoogleSignInAccount?> signIn() async {
    _lastSignInError = null;
    try {
      _currentUser = await _googleSignIn.signIn();
      _driveApi = null;
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
  }

  Future<bool> isSignedIn() async {
    // Rely on cached user if available, otherwise check plugin
    if (_currentUser != null) return true;
    return await _googleSignIn.isSignedIn();
  }

  /// Checks if there is basic internet connectivity.
  Future<bool> _hasConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 3),
      );
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

    // If forcing, we try to re-authenticate silently to refresh tokens
    if (force) {
      try {
        _currentUser =
            await _googleSignIn.signInSilently(reAuthenticate: true).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => _currentUser,
                );
      } catch (e) {
        if (kDebugMode) {
          print('Forced re-authentication failed: $e');
        }
      }
    }

    // Silent sign-in only for background/automated tasks
    final user = await currentUser;

    if (user != null) {
      try {
        final authClient = await _googleSignIn.authenticatedClient();
        if (authClient != null) {
          _driveApi = drive.DriveApi(authClient);
        } else {
          // Force a re-authentication state if we have a user but no client
          _currentUser = null;
          _driveApi = null;
          await _googleSignIn.signOut();
          throw Exception('Not signed in to Google Drive (Token expired)');
        }
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
      final folderList = await _driveApi!.files.list(q: query).timeout(
            const Duration(seconds: 10),
          );

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
      final fileList = await _driveApi!.files
          .list(
            q: query,
            $fields: 'files(id, name, modifiedTime, size)',
          )
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint(
          'listSyncFiles: Found ${fileList.files?.length ?? 0} files in Drive',
        );
        for (final f in fileList.files ?? []) {
          debugPrint('  - ${f.name}');
        }
      }

      return fileList.files ?? [];
    });
  }

  Future<void> downloadFile(String fileId, File targetFile) async {
    await _executeWithRetry(() async {
      final mediaResponse = await _driveApi!.files
          .get(
            fileId,
            downloadOptions: drive.DownloadOptions.fullMedia,
          )
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
