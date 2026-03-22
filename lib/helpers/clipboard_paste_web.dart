// Web-specific clipboard image paste support
// This file uses dart:html which is only available on web
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

typedef OnImagePasted = Future<void> Function(Uint8List bytes, String mimeType);

StreamSubscription<html.Event>? _pasteSubscription;

/// Sets up a global paste listener for web.
void setupWebPasteListener(OnImagePasted onImagePasted) {
  _pasteSubscription?.cancel();
  _pasteSubscription = html.document.onPaste.listen((html.Event event) async {
    final clipboardData = (event as dynamic).clipboardData;
    if (clipboardData == null) return;

    final items = clipboardData.items;
    if (items == null) return;

    final int length = items.length as int;
    for (int i = 0; i < length; i++) {
      final item = items[i];
      final String type = item.type as String;
      if (type.startsWith('image/')) {
        event.preventDefault();
        final blob = item.getAsFile();
        if (blob == null) continue;

        final reader = html.FileReader();
        final completer = Completer<Uint8List>();

        reader.onLoad.listen((_) {
          final result = reader.result;
          if (result is Uint8List) {
            completer.complete(result);
          } else if (result is List<int>) {
            completer.complete(Uint8List.fromList(result));
          } else {
            completer.completeError('Unexpected result type');
          }
        });
        reader.onError.listen((_) {
          completer.completeError('Failed to read pasted image');
        });
        reader.readAsArrayBuffer(blob);

        try {
          final bytes = await completer.future;
          await onImagePasted(bytes, type);
        } catch (_) {}
        break; // Only handle first image
      }
    }
  });
}

/// Removes the paste listener
void disposeWebPasteListener() {
  _pasteSubscription?.cancel();
  _pasteSubscription = null;
}
