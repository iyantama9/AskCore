import 'api_service.dart';

class ChatService {
  /// Fallback model catalog used while the server catalog is loading/unavailable.
  static const List<ModelInfo> allModels = [
    ModelInfo(
      id: 'mk/sonnet-4.5',
      ownedBy: 'Anthropic',
      displayNameOverride: 'Sonnet 4.5',
      supportsReasoning: true,
      supportsVision: true,
      supportsBrowse: true,
      costTier: 'premium',
    ),
    ModelInfo(
      id: 'mk/sonnet-4.5-thinking',
      ownedBy: 'Anthropic',
      displayNameOverride: 'Sonnet 4.5',
      supportsReasoning: true,
      supportsVision: true,
      supportsBrowse: true,
      costTier: 'premium',
    ),
    ModelInfo(
      id: 'dh/moonshotai/Kimi-K2.6',
      ownedBy: 'Moonshot',
      displayNameOverride: 'Kimi K2.6',
      supportsVision: true,
      supportsBrowse: true,
      costTier: 'standard',
    ),
    ModelInfo(
      id: 'qc/glm-5.2',
      ownedBy: 'Zhipu',
      displayNameOverride: 'GLM 5.2',
      supportsVision: true,
      supportsBrowse: true,
      costTier: 'standard',
    ),
    ModelInfo(
      id: 'kc/minimax-m3',
      ownedBy: 'MiniMax',
      displayNameOverride: 'MiniMax M3',
      supportsBrowse: true,
      costTier: 'standard',
    ),
    ModelInfo(
      id: 'qc/qwen-image-2.0',
      ownedBy: 'Alibaba',
      displayNameOverride: 'Qwen Image 2.0',
      supportsImageGen: true,
      costTier: 'image',
    ),
    ModelInfo(
      id: 'qc/qwen-image-2.0-pro',
      ownedBy: 'Alibaba',
      displayNameOverride: 'Qwen Image Pro',
      supportsImageGen: true,
      costTier: 'image',
    ),
  ];

  Future<List<ModelInfo>> getModels() async {
    try {
      final models = await ApiService().getModels();
      return models.map(ModelInfo.fromJson).toList();
    } catch (_) {
      return allModels;
    }
  }
}

class ModelInfo {
  final String id;
  final String ownedBy;
  final String? displayNameOverride;
  final bool supportsReasoning;
  final bool supportsVision;
  final bool supportsImageGen;
  final bool supportsBrowse;
  final String costTier;

  const ModelInfo({
    required this.id,
    required this.ownedBy,
    this.displayNameOverride,
    this.supportsReasoning = false,
    this.supportsVision = false,
    this.supportsImageGen = false,
    this.supportsBrowse = false,
    this.costTier = 'standard',
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id']?.toString() ?? '',
      ownedBy: json['owned_by']?.toString() ?? json['ownedBy']?.toString() ?? 'Unknown',
      displayNameOverride:
          json['display_name']?.toString() ?? json['displayName']?.toString(),
      supportsReasoning: json['supports_reasoning'] == true,
      supportsVision: json['supports_vision'] == true,
      supportsImageGen: json['supports_image_generation'] == true,
      supportsBrowse: json['supports_browse'] == true,
      costTier: json['cost_tier']?.toString() ?? 'standard',
    );
  }

  String get displayName => displayNameOverride ?? id;

  String get provider => ownedBy;
}

class ChatException implements Exception {
  final String message;
  const ChatException(this.message);

  @override
  String toString() => message;
}
