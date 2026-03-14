import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  await api.loadToken();
  runApp(AskCoreApp(isLoggedIn: api.isLoggedIn));
}

class AskCoreApp extends StatefulWidget {
  final bool isLoggedIn;

  const AskCoreApp({super.key, required this.isLoggedIn});

  static AskCoreAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<AskCoreAppState>();

  @override
  State<AskCoreApp> createState() => AskCoreAppState();
}

class AskCoreAppState extends State<AskCoreApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  late bool _isLoggedIn;

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _isLoggedIn = widget.isLoggedIn;
  }

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _handleLoginSuccess() {
    setState(() => _isLoggedIn = true);
  }

  void _handleLogout() async {
    await ApiService().clearToken();
    setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AskCore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: _isLoggedIn
          ? ChatScreen(onLogout: _handleLogout)
          : LoginScreen(onLoginSuccess: _handleLoginSuccess),
    );
  }
}
