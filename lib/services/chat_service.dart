import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatService {
  static const String _baseUrl = 'https://router.getcore.id/v1';
  static const String _apiKey = 'intern1';

  /// All available models from the router, hardcoded for instant loading.
  static const List<ModelInfo> allModels = [
    ModelInfo(id: 'gemini-2.5-flash', ownedBy: 'Google'),
    ModelInfo(id: 'gemini-2.5-flash-lite', ownedBy: 'Google'),
    ModelInfo(id: 'gemini-2.5-pro', ownedBy: 'Google'),
    ModelInfo(id: 'gemini-3-flash-preview', ownedBy: 'Google'),
    ModelInfo(id: 'gemini-3-pro-image-preview', ownedBy: 'Google'),
    ModelInfo(id: 'gemini-3-pro-preview', ownedBy: 'Google'),
    ModelInfo(id: 'gpt-5', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.1', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.1-codex', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.1-codex-max', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.1-codex-mini', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.2', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5.2-codex', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5-codex', ownedBy: 'OpenAI'),
    ModelInfo(id: 'gpt-5-codex-mini', ownedBy: 'OpenAI'),
  ];

  Future<List<ModelInfo>> getModels() async {
    // Return hardcoded models instantly — no network request needed
    return allModels;
  }
}

class ModelInfo {
  final String id;
  final String ownedBy;

  const ModelInfo({required this.id, required this.ownedBy});

  String get displayName {
    return id
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
  }

  String get provider => ownedBy;

  bool get supportsImageGen => id.contains('image');
}

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);

  @override
  String toString() => message;
}
