import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// Helpers for images that may be stored either as a base64 `data:` URI (our
/// free, Firestore-backed attachment scheme — see `AttachmentStore`) or as an
/// ordinary http(s) URL (e.g. the Google account photo).

bool isDataUri(String s) => s.startsWith('data:');

/// Decode the bytes from a `data:...;base64,....` URI, or null if [s] isn't one.
Uint8List? bytesFromDataUri(String s) {
  if (!isDataUri(s)) return null;
  final comma = s.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(s.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Wrap raw JPEG [bytes] as a `data:image/jpeg;base64,...` URI (used for the
/// small, always-displayed profile photo, stored inline on the profile).
String jpegDataUri(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

/// An [ImageProvider] for either scheme, or null when [url] is empty — so the
/// same avatar/preview widgets work whether the image is a Google URL or a
/// locally stored base64 photo.
ImageProvider? imageProviderFor(String? url) {
  if (url == null || url.isEmpty) return null;
  final bytes = bytesFromDataUri(url);
  if (bytes != null) return MemoryImage(bytes);
  return NetworkImage(url);
}

/// Downscale + re-encode [src] to a bounded JPEG so it's small enough to live
/// in a single Firestore document (base64 inflates bytes ~33%, and a doc caps
/// at 1 MiB). Pure Dart, so it behaves the same on web and mobile. Returns the
/// original bytes unchanged if decoding fails (caller still size-checks).
Uint8List encodeBoundedJpeg(
  Uint8List src, {
  int maxWidth = 1200,
  int quality = 60,
}) {
  final decoded = img.decodeImage(src);
  if (decoded == null) return src;
  final resized = decoded.width > maxWidth
      ? img.copyResize(decoded, width: maxWidth)
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}
