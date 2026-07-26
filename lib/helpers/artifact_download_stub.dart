import 'dart:typed_data';

/// Stub implementation for non-web platforms
/// On mobile, downloads are handled via share dialog or system downloads
void downloadFileAsBytes(Uint8List bytes, String filename) {
  // On mobile, we don't need browser-style downloads
  // The file bytes are already available for display/share
  throw UnsupportedError('Browser download not available on this platform');
}
