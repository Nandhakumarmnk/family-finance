import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Thin wrapper over the Google Drive v3 API for the handful of operations
/// the app needs: find-or-create a folder, find a file by name, download
/// bytes, upload/overwrite bytes, and share a file with another email.
class DriveService {
  DriveService(http.Client client) : _api = drive.DriveApi(client);

  final drive.DriveApi _api;

  static const String appFolderName = 'FamilyFinance';
  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Run a Drive API call, turning opaque `DetailedApiRequestError`s into a
  /// message that names the operation and includes Google's full error JSON
  /// (which spells out exactly which field/value it rejected).
  Future<T> _run<T>(String op, Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      throw Exception('Drive.$op failed: ${_describe(e)}');
    }
  }

  String _describe(Object e) {
    try {
      final json = (e as dynamic).jsonResponse;
      if (json != null) return '$e | ${jsonEncode(json)}';
    } catch (_) {}
    return e.toString();
  }

  /// Returns the id of the `FamilyFinance` folder, creating it if missing.
  Future<String> ensureAppFolder() => _run('ensureAppFolder', () async {
        final existing = await _api.files.list(
          q: "name='$appFolderName' and "
              "mimeType='application/vnd.google-apps.folder' and trashed=false",
          $fields: 'files(id,name)',
          spaces: 'drive',
        );
        if (existing.files != null && existing.files!.isNotEmpty) {
          return existing.files!.first.id!;
        }
        final folder = drive.File()
          ..name = appFolderName
          ..mimeType = 'application/vnd.google-apps.folder';
        final created = await _api.files.create(folder, $fields: 'id');
        return created.id!;
      });

  /// Find a file id by name within [parentId]. Returns null if not present.
  Future<String?> findFile(String name, {required String parentId}) {
    final escapedName = name.replaceAll("'", r"\'");
    // If we somehow have no parent id, search by name alone rather than
    // sending an empty-id clause (which Drive rejects as an invalid query).
    final q = parentId.isEmpty
        ? "name='$escapedName' and trashed=false"
        : "name='$escapedName' and '$parentId' in parents and trashed=false";
    return _run('findFile q=[$q]', () async {
      final res = await _api.files.list(
        q: q,
        $fields: 'files(id,name,modifiedTime)',
        spaces: 'drive',
      );
      if (res.files != null && res.files!.isNotEmpty) {
        return res.files!.first.id;
      }
      return null;
    });
  }

  /// Find a file by name anywhere the signed-in user can reach it — including
  /// files another family member created and shared with them ("Shared with
  /// me"), which is how the shared family workbook is located on a member's
  /// device. Returns the OLDEST match (the original, owner-created copy) so
  /// every member converges on a single canonical workbook even if an older
  /// build of the app left behind a duplicate fork in someone's own folder.
  Future<String?> findSharedFile(String name) {
    final escapedName = name.replaceAll("'", r"\'");
    final q = "name='$escapedName' and trashed=false";
    return _run('findSharedFile q=[$q]', () async {
      final res = await _api.files.list(
        q: q,
        $fields: 'files(id,name,createdTime)',
        orderBy: 'createdTime', // ascending — oldest first
        spaces: 'drive',
      );
      final files = res.files;
      if (files == null || files.isEmpty) return null;
      return files.first.id;
    });
  }

  /// Download a file's raw bytes by id.
  Future<Uint8List> downloadBytes(String fileId) =>
      _run('downloadBytes', () async {
        final media = await _api.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;

        final out = <int>[];
        await for (final chunk in media.stream) {
          out.addAll(chunk);
        }
        return Uint8List.fromList(out);
      });

  /// Create a new .xlsx file with [bytes], returning its id.
  Future<String> createXlsx(
    String name,
    List<int> bytes, {
    required String parentId,
  }) =>
      _run('createXlsx', () async {
        if (bytes.isEmpty) {
          throw Exception('refusing to upload an empty workbook');
        }
        final meta = drive.File()..name = name;
        // Only set a parent when we actually have one — an empty/invalid id is
        // rejected by Drive as an invalid value.
        if (parentId.isNotEmpty) meta.parents = [parentId];

        final media = drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: _xlsxMime,
        );
        final created = await _api.files.create(
          meta,
          uploadMedia: media,
          $fields: 'id',
        );
        return created.id!;
      });

  /// Overwrite an existing file's content with [bytes].
  Future<void> updateXlsx(String fileId, List<int> bytes) =>
      _run('updateXlsx', () async {
        if (bytes.isEmpty) {
          throw Exception('refusing to upload an empty workbook');
        }
        final media = drive.Media(
          Stream.value(bytes),
          bytes.length,
          contentType: _xlsxMime,
        );
        await _api.files.update(drive.File(), fileId, uploadMedia: media);
      });

  /// Convenience: create the file if missing, otherwise overwrite it.
  /// Returns the file id.
  Future<String> upsertXlsx(
    String name,
    List<int> bytes, {
    required String parentId,
  }) async {
    final existingId = await findFile(name, parentId: parentId);
    if (existingId == null) {
      return createXlsx(name, bytes, parentId: parentId);
    }
    await updateXlsx(existingId, bytes);
    return existingId;
  }

  /// Share a file with another user (used to invite family members to the
  /// shared family workbook). [role] is typically "writer" or "reader".
  Future<void> shareWith(
    String fileId,
    String email, {
    String role = 'writer',
  }) =>
      _run('shareWith', () async {
        final permission = drive.Permission()
          ..type = 'user'
          ..role = role
          ..emailAddress = email;
        await _api.permissions.create(
          permission,
          fileId,
          sendNotificationEmail: true,
        );
      });

  /// A short, shareable link the user can copy to invite family members.
  Future<String?> webLink(String fileId) => _run('webLink', () async {
        final f =
            await _api.files.get(fileId, $fields: 'webViewLink') as drive.File;
        return f.webViewLink;
      });
}
