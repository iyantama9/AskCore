import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/chat_input.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _token;
  String? _username;
  int? _userId;

  String? get token => _token;
  String? get username => _username;
  int? get userId => _userId;
  bool get isLoggedIn => _token != null;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _username = prefs.getString('auth_username');
    _userId = prefs.getInt('auth_user_id');
  }

  Future<void> _saveToken(String token, String username, int userId) async {
    _token = token;
    _username = username;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('auth_username', username);
    await prefs.setInt('auth_user_id', userId);
  }

  Future<void> clearToken() async {
    _token = null;
    _username = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_username');
    await prefs.remove('auth_user_id');
  }

  // Auth
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveToken(
        data['token'],
        data['user']['username'],
        data['user']['id'],
      );
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw ApiException(error['error'] ?? 'Login failed');
    }
  }

  // Chats
  Future<List<Map<String, dynamic>>> getChats() async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/chats'),
      headers: _authHeaders,
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw ApiException('Failed to load chats');
  }

  Future<Map<String, dynamic>> createChat({String? model}) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/chats'),
      headers: _authHeaders,
      body: jsonEncode({'model': model ?? AppConstants.defaultModel}),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw ApiException('Failed to create chat');
  }

  Future<void> renameChat(int chatId, String title) async {
    final response = await http.put(
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId'),
      headers: _authHeaders,
      body: jsonEncode({'title': title}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to rename chat');
    }
  }

  Future<void> deleteChat(int chatId) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to delete chat');
    }
  }

  Future<void> updateChatModel(int chatId, String model) async {
    final response = await http.put(
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId'),
      headers: _authHeaders,
      body: jsonEncode({'title': null, 'model': model}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to update model');
    }
  }

  // Messages
  Future<List<Map<String, dynamic>>> getMessages(int chatId) async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId/messages'),
      headers: _authHeaders,
    );
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw ApiException('Failed to load messages');
  }

  Future<Map<String, dynamic>> sendMessage(
    int chatId,
    String content, {
    List<PendingFile>? files,
    List<String>? tools,
  }) async {
    final body = <String, dynamic>{
      'content': content,
    };

    if (files != null && files.isNotEmpty) {
      body['file_urls'] = files.map((f) => f.url).toList();
      body['file_names'] = files.map((f) => f.name).toList();
      body['file_url'] = files.first.url;
      body['file_name'] = files.first.name;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
    }

    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/chats/$chatId/messages'),
      headers: _authHeaders,
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    final error = jsonDecode(response.body);
    throw ApiException(error['error'] ?? 'Failed to send message');
  }

  // Upload
  Future<Map<String, dynamic>> uploadFile(
    List<int> bytes,
    String fileName,
    String contentType,
  ) async {
    final uri = Uri.parse('${AppConstants.backendUrl}/api/upload');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $_token';

    final parts = contentType.split('/');
    final mediaType = parts.length == 2
        ? http_parser.MediaType(parts[0], parts[1])
        : http_parser.MediaType('application', 'octet-stream');

    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: fileName,
      contentType: mediaType,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw ApiException('Upload failed');
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}
