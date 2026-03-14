enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;
  final bool isThinking;  // "Thinking..." phase
  final bool isTyping;    // Typewriter reveal phase
  final int revealedChars; // How many chars are revealed

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.isThinking = false,
    this.isTyping = false,
    this.revealedChars = 0,
  });

  factory ChatMessage.user(String content) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  factory ChatMessage.thinking() {
    return ChatMessage(
      id: 'thinking_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
      isThinking: true,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? content,
    bool? isLoading,
    bool? isThinking,
    bool? isTyping,
    int? revealedChars,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isLoading: isLoading ?? this.isLoading,
      isThinking: isThinking ?? this.isThinking,
      isTyping: isTyping ?? this.isTyping,
      revealedChars: revealedChars ?? this.revealedChars,
    );
  }

  /// The text to actually display (for typewriter effect)
  String get displayContent {
    if (isTyping && revealedChars < content.length) {
      return content.substring(0, revealedChars);
    }
    return content;
  }

  Map<String, String> toApiMessage() {
    return {'role': role.name, 'content': content};
  }
}
