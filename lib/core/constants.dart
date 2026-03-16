
class AppConstants {
  AppConstants._();

  static const String appName = 'AskCore';

  /// Production backend on VPS
  /// For local dev, change to: 'http://localhost:4000'
  static const String backendUrl = 'http://143.198.214.130:4000';

  static const String defaultModel = 'gemini-2.5-flash-lite';

  static const double maxChatWidth = 800.0;
  static const double mobileBreakpoint = 600.0;
  static const double sidebarBreakpoint = 900.0;
  static const double sidebarWidth = 280.0;

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationNormal = Duration(milliseconds: 350);
  static const Duration animationSlow = Duration(milliseconds: 500);

  static const int maxFileSize = 1 * 1024 * 1024; // 1MB

  static const List<String> suggestions = [
    '✨ Jelaskan komputer kuantum secara sederhana',
    '📝 Buatkan puisi singkat tentang bintang',
    '💡 Kasih 5 ide startup kreatif',
    '🧑‍💻 Jelaskan async/await di Dart',
  ];
}
