// Web-specific clipboard image paste support, implemented with package:web
// + dart:js_interop so it compiles under both dart2js and dart2wasm.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

typedef OnImagePasted = Future<void> Function(Uint8List bytes, String mimeType);

JSFunction? _pasteHandler;

/// Sets up a global paste listener for web.
void setupWebPasteListener(OnImagePasted onImagePasted) {
  disposeWebPasteListener();
  void handler(web.Event event) {
    _handlePaste(event, onImagePasted);
  }

  final jsHandler = handler.toJS;
  _pasteHandler = jsHandler;
  web.document.addEventListener('paste', jsHandler);
}

void _handlePaste(web.Event event, OnImagePasted onImagePasted) {
  final clipboardData = (event as web.ClipboardEvent).clipboardData;
  if (clipboardData == null) return;

  final files = clipboardData.files;
  for (var i = 0; i < files.length; i++) {
    final file = files.item(i);
    if (file == null) continue;
    final type = file.type;
    if (!type.startsWith('image/')) continue;

    event.preventDefault();
    _readAndDeliver(file, type, onImagePasted);
    break; // Only handle first image
  }
}

Future<void> _readAndDeliver(
  web.File file,
  String type,
  OnImagePasted onImagePasted,
) async {
  try {
    final buffer = await file.arrayBuffer().toDart;
    await onImagePasted(buffer.toDart.asUint8List(), type);
  } catch (_) {}
}

/// Removes the paste listener
void disposeWebPasteListener() {
  final handler = _pasteHandler;
  if (handler != null) {
    web.document.removeEventListener('paste', handler);
    _pasteHandler = null;
  }
}
