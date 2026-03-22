// Non-web stub for clipboard image paste support
import 'dart:typed_data';

typedef OnImagePasted = Future<void> Function(Uint8List bytes, String mimeType);

/// No-op on non-web platforms
void setupWebPasteListener(OnImagePasted onImagePasted) {
  // Clipboard image paste not supported on mobile/desktop
  // Users should use the file picker instead
}

/// No-op on non-web platforms
void disposeWebPasteListener() {}
