// Conditional import for clipboard paste support
// Uses package:web on web (js + wasm), no-op stub on other platforms
export 'clipboard_paste_stub.dart'
    if (dart.library.js_interop) 'clipboard_paste_web.dart';
