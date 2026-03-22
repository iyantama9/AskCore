// Conditional import for clipboard paste support
// Uses dart:html on web, no-op stub on other platforms
export 'clipboard_paste_stub.dart'
    if (dart.library.html) 'clipboard_paste_web.dart';
