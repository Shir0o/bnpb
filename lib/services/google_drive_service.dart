import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: Platform.isMacOS
        ? '228185988095-9soj0hn2t78nnfbe1bt5amt54tjtnap2.apps.googleusercontent.com'
        : null,
    serverClientId: Platform.isAndroid
        ? '228185988095-j6gjirouvrt8o71q6bs1ubco9a2gdm8f.apps.googleusercontent.com'
        : null,
    scopes: [drive.DriveApi.driveFileScope],
  );

  bool _triedSilentSignIn = false;
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  String? _lastSignInError;

  /// Returns the latest error message from a sign-in attempt.
  String? get lastSignInError => _lastSignInError;

  /// Returns the current user, attempting silent sign-in if necessary.
  /// Does NOT initialize the Drive API client to avoid unnecessary keychain access.
  Future<GoogleSignInAccount?> get currentUser async {
    if (_currentUser != null) return _currentUser;
    if (_triedSilentSignIn) return null;

    try {
      // Use a timeout to prevent hanging on poor connections.
      // Silent sign-in should be fast; if it's not, we'd rather skip it than block.
      _currentUser = await _googleSignIn.signInSilently().timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
    } catch (e) {
      if (kDebugMode) {
        print('Silent sign-in failed/timed out: $e');
      }
      _currentUser = null;
    }

    _triedSilentSignIn = true;
    return _currentUser;
  }

  /// explicit sign in - usually triggered by user interaction
  Future<GoogleSignInAccount?> signIn() async {
    _lastSignInError = null;
    try {
      _currentUser = await _googleSignIn.signIn();
      _triedSilentSignIn = true;
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
    _triedSilentSignIn = false;
  }

  Future<bool> isSignedIn() async {
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
  Future<void> _ensureApiInitialized() async {
    if (!await _hasConnectivity()) {
      throw Exception('No internet connection');
    }

    if (_driveApi != null) {
      try {
        final _ = await _googleSignIn.authenticatedClient();
        return; // still good
      } catch (_) {
        _driveApi = null; // force re-init
      }
    }

    // Silent sign-in only for background/automated tasks
    final user = await currentUser;

    if (user != null) {
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient != null) {
        _driveApi = drive.DriveApi(authClient);
      } else {
        // Force a re-authentication state if we have a user but no client
        _currentUser = null;
        await _googleSignIn.signOut();
        throw Exception('Not signed in to Google Drive (Token expired)');
      }
    } else {
      throw Exception('Not signed in to Google Drive (Silent sign-in failed)');
    }
  }

  /// Finds a folder by name, or creates it if it doesn't exist.
  Future<String?> _getOrCreateFolder(String folderName) async {
    // API must be initialized by caller
    if (_driveApi == null) return null;

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
  }

  Future<void> uploadFile(
    File localFile,
    String remoteName, {
    String folderName = 'BNPB-Sync',
  }) async {
    await _ensureApiInitialized();
    if (_driveApi == null) {
      throw Exception('Not signed in to Google Drive');
    }

    final folderId = await _getOrCreateFolder(folderName);

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
  }

  Future<List<drive.File>> listSyncFiles({
    String folderName = 'BNPB-Sync',
  }) async {
    await _ensureApiInitialized();
    if (_driveApi == null) {
      if (kDebugMode) {
        print('listSyncFiles: _driveApi is null, returning empty list');
      }
      return [];
    }

    final folderId = await _getOrCreateFolder(folderName);
    if (folderId == null) {
      if (kDebugMode) {
        print('listSyncFiles: folderId is null, returning empty list');
      }
      return [];
    }

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
  }

  Future<void> downloadFile(String fileId, File targetFile) async {
    await _ensureApiInitialized();
    if (_driveApi == null) {
      throw Exception('Not signed in to Google Drive');
    }

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
  }
}
