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
    scopes: [
      drive.DriveApi.driveFileScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        final authClient = await _googleSignIn.authenticatedClient();
        if (authClient != null) {
          _driveApi = drive.DriveApi(authClient);
        }
      }
      return _currentUser;
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In failed: $e');
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
    return await _googleSignIn.isSignedIn();
  }

  Future<GoogleSignInAccount?> get currentUser async {
    _currentUser ??= await _googleSignIn.signInSilently();
    if (_currentUser != null && _driveApi == null) {
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient != null) {
        _driveApi = drive.DriveApi(authClient);
      }
    }
    return _currentUser;
  }

  /// Finds a folder by name, or creates it if it doesn't exist.
  Future<String?> _getOrCreateFolder(String folderName) async {
    if (_driveApi == null) return null;

    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
    final folderList = await _driveApi!.files.list(q: query);

    if (folderList.files != null && folderList.files!.isNotEmpty) {
      return folderList.files!.first.id;
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await _driveApi!.files.create(folder);
    return createdFolder.id;
  }

  Future<void> uploadFile(File localFile, String remoteName,
      {String folderName = 'BNPB-Sync'}) async {
    if (_driveApi == null) {
      await currentUser;
      if (_driveApi == null) throw Exception('Not signed in to Google Drive');
    }

    final folderId = await _getOrCreateFolder(folderName);

    final query =
        "name = '$remoteName' and '$folderId' in parents and trashed = false";
    final existingFiles = await _driveApi!.files.list(q: query);

    final driveFile = drive.File()..name = remoteName;

    final media = drive.Media(localFile.openRead(), localFile.lengthSync());

    if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
      // Update existing file
      await _driveApi!.files.update(driveFile, existingFiles.files!.first.id!,
          uploadMedia: media);
    } else {
      // Create new file
      if (folderId != null) {
        driveFile.parents = [folderId];
      }
      await _driveApi!.files.create(driveFile, uploadMedia: media);
    }
  }

  Future<List<drive.File>> listSyncFiles(
      {String folderName = 'BNPB-Sync'}) async {
    if (_driveApi == null) {
      await currentUser;
      if (_driveApi == null) return [];
    }

    final folderId = await _getOrCreateFolder(folderName);
    if (folderId == null) return [];

    final query = "'$folderId' in parents and trashed = false";
    final fileList = await _driveApi!.files
        .list(q: query, $fields: 'files(id, name, modifiedTime, size)');

    return fileList.files ?? [];
  }

  Future<void> downloadFile(String fileId, File targetFile) async {
    if (_driveApi == null) {
      await currentUser;
      if (_driveApi == null) throw Exception('Not signed in to Google Drive');
    }

    // To download content we use get() with downloadOptions: drive.DownloadOptions.fullMedia
    final mediaResponse = await _driveApi!.files.get(fileId,
        downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;

    final List<int> data = [];
    await for (final chunk in mediaResponse.stream) {
      data.addAll(chunk);
    }
    await targetFile.writeAsBytes(data);
  }
}
