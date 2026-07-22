import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../helpers/clipboard_paste.dart';
import '../core/constants.dart';
import '../main.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/chat_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_selector.dart';
import '../widgets/welcome_view.dart';
import 'playground_screen.dart';

class _RetryPayload {
  final String content;
  final List<PendingFile> files;
  final Set<ChatTool> tools;

  const _RetryPayload({
    required this.content,
    required this.files,
    required this.tools,
  });
}

class ChatScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ChatScreen({super.key, required this.onLogout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _chats = [];
  List<ChatMessage> _messages = [];
  List<ModelInfo> _models = ChatService.allModels;
  int? _selectedChatId;
  String _currentModel = AppConstants.defaultModel;
  bool _isLoading = false;
  bool _sidebarOpen = true;
  _RetryPayload? _lastRetryPayload;
  String? _usageWarning;
  // Only animate the LATEST 2 messages (user + assistant)
  final Map<String, AnimationController> _animControllers = {};

  // File attachments (up to 5)
  List<PendingFile> _pendingFiles = [];

  // Active tools
  final Set<ChatTool> _activeTools = {};

  // Reasoning toggle for Claude Sonnet models
  bool _reasoningEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadModelCatalog();
    _loadChats();
    _loadUsage();
    // Setup web clipboard paste listener for images
    setupWebPasteListener(_onImagePasted);
  }

  Future<void> _loadModelCatalog() async {
    final models = await ChatService().getModels();
    if (!mounted) return;
    setState(() {
      _models = models.isEmpty ? ChatService.allModels : models;
      if (!_models.any((m) => m.id == _currentModel)) {
        _currentModel = _models.first.id;
      }
    });
  }

  Future<void> _loadUsage() async {
    if (!_api.isLoggedIn) return;
    try {
      final data = await _api.getUsage();
      final usage = List<Map<String, dynamic>>.from(data['usage'] as List);
      final nearLimit = usage.where((item) {
        final percent = (item['percent'] as num?)?.toDouble() ?? 0;
        return percent >= 0.8;
      }).toList();
      if (!mounted) return;
      setState(() {
        _usageWarning = nearLimit.isEmpty
            ? null
            : 'Quota hampir habis: ${nearLimit.map((e) => e['kind']).join(', ')}';
      });
    } catch (_) {}
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _formatError(String message, {String? code, String? requestId}) {
    final parts = <String>[message];
    if (code != null && code.isNotEmpty) parts.add('Kode: $code');
    if (requestId != null && requestId.isNotEmpty) parts.add('ID: $requestId');
    return '⚠️ ${parts.join('\n')}';
  }

  Future<void> _onImagePasted(Uint8List bytes, String mimeType) async {
    if (_pendingFiles.length >= 5) return;
    final ext = mimeType.split('/').last;
    final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      final result = await _api.uploadFile(bytes, fileName, mimeType);
      if (mounted) {
        setState(() {
          _pendingFiles.add(
            PendingFile(
              url: result['key'] ?? '',
              name: result['file_name'] ?? fileName,
            ),
          );
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    disposeWebPasteListener();
    _scrollController.dispose();
    for (final c in _animControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final chats = await _api.getChats();
      if (mounted) setState(() => _chats = chats);
    } catch (_) {}
  }

  Future<void> _loadMessages(int chatId) async {
    _cleanupAnimControllers();

    try {
      final msgs = await _api.getMessages(chatId);
      if (mounted) {
        setState(() {
          _messages = msgs
              .map(
                (m) => ChatMessage(
                  id: m['id'].toString(),
                  role: m['role'] == 'user'
                      ? MessageRole.user
                      : MessageRole.assistant,
                  content: m['content'] ?? '',
                  timestamp:
                      DateTime.tryParse(m['created_at'] ?? '') ??
                      DateTime.now(),
                ),
              )
              .toList();
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  void _cleanupAnimControllers() {
    for (final c in _animControllers.values) {
      c.dispose();
    }
    _animControllers.clear();
  }

  AnimationController _createAnimController() {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    controller.forward();
    return controller;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _selectChat(int chatId) async {
    setState(() => _selectedChatId = chatId);
    await _loadMessages(chatId);

    // Sync reasoning toggle based on loaded model
    final chat = _chats.firstWhere((c) => c['id'] == chatId);
    final model = chat['model'] as String? ?? _currentModel;
    setState(() {
      _currentModel = model;
      _reasoningEnabled = model == 'mk/sonnet-4.5-thinking';
      if (_reasoningEnabled) {
        _activeTools.add(ChatTool.reasoning);
      } else {
        _activeTools.remove(ChatTool.reasoning);
      }
    });

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _createNewChat() async {
    try {
      final chat = await _api.createChat(model: _currentModel);
      await _loadChats();
      await _selectChat(chat['id']);
    } catch (_) {}
  }

  Future<void> _renameChat(int chatId, String newTitle) async {
    try {
      await _api.renameChat(chatId, newTitle);
      await _loadChats();
    } catch (_) {}
  }

  Future<void> _deleteChat(int chatId) async {
    try {
      await _api.deleteChat(chatId);
      if (_selectedChatId == chatId) {
        setState(() {
          _selectedChatId = null;
          _messages.clear();
        });
      }
      await _loadChats();
    } catch (_) {}
  }

  void _retryLastMessage() {
    final payload = _lastRetryPayload;
    if (payload == null || _isLoading) return;

    setState(() {
      if (_messages.isNotEmpty && _messages.last.isError) {
        _messages.removeLast();
      }
      if (_messages.isNotEmpty && _messages.last.role == MessageRole.user) {
        _messages.removeLast();
      }
    });

    _sendMessage(payload.content, retryPayload: payload);
  }

  void _handleReasoningToggle(bool enabled) {
    setState(() {
      _reasoningEnabled = enabled;
      if (enabled) {
        _activeTools.add(ChatTool.reasoning);
      } else {
        _activeTools.remove(ChatTool.reasoning);
      }

      // Auto-switch between Sonnet base and thinking variants
      if (_currentModel == 'mk/sonnet-4.5' ||
          _currentModel == 'mk/sonnet-4.5-thinking') {
        _currentModel = enabled ? 'mk/sonnet-4.5-thinking' : 'mk/sonnet-4.5';

        // Persist to database
        if (_selectedChatId != null) {
          _api.updateChatModel(_selectedChatId!, _currentModel);
        }
      }
    });
  }

  Future<void> _sendMessage(
    String content, {
    _RetryPayload? retryPayload,
  }) async {
    if (_isLoading) return;

    if (_selectedChatId == null) {
      try {
        final chat = await _api.createChat(model: _currentModel);
        setState(() => _selectedChatId = chat['id']);
        await _loadChats();
      } catch (_) {
        return;
      }
    }

    final filesForSend =
        retryPayload?.files ?? List<PendingFile>.from(_pendingFiles);
    final toolsForSend =
        retryPayload?.tools ?? Set<ChatTool>.from(_activeTools);
    _lastRetryPayload = _RetryPayload(
      content: content,
      files: filesForSend,
      tools: toolsForSend,
    );

    String userContent = content;
    if (filesForSend.isNotEmpty) {
      final names = filesForSend.map((f) => '📎 ${f.name}').join('\n');
      userContent += '\n\n$names';
    }

    // Clean up old animation controllers
    _cleanupAnimControllers();

    final userMsg = ChatMessage.user(userContent);
    final userAnim = _createAnimController();
    _animControllers[userMsg.id] = userAnim;

    final thinkingMsg = ChatMessage.thinking();
    final thinkingAnim = _createAnimController();
    _animControllers[thinkingMsg.id] = thinkingAnim;

    setState(() {
      _messages.add(userMsg);
      _messages.add(thinkingMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    final toolsList = toolsForSend
        .where((tool) => tool != ChatTool.reasoning)
        .map(
          (tool) => tool == ChatTool.browseWeb ? 'browse_web' : 'create_image',
        )
        .toList();
    final pendingFilesCopy = List<PendingFile>.from(filesForSend);

    try {
      String accumulated = '';
      bool firstToken = true;
      final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
      int tokenCount = 0;
      const updateInterval = 3; // Update UI every 3 tokens to reduce lag

      await for (final event in _api.sendMessageStream(
        _selectedChatId!,
        content,
        files: pendingFilesCopy,
        tools: toolsList,
      )) {
        if (!mounted) break;

        switch (event.type) {
          case SseEventType.token:
            accumulated += event.token ?? '';
            tokenCount++;

            // Only update UI every N tokens or on first token
            if (firstToken && idx != -1) {
              firstToken = false;
              setState(() {
                _messages[idx] = ChatMessage(
                  id: thinkingMsg.id,
                  role: MessageRole.assistant,
                  content: accumulated,
                  timestamp: DateTime.now(),
                  isLoading: false,
                  isThinking: false,
                  isTyping: false,
                  revealedChars: accumulated.length,
                );
                _pendingFiles = [];
              });
              _scrollToBottom();
            } else if (idx != -1 && tokenCount >= updateInterval) {
              tokenCount = 0; // Reset counter
              setState(() {
                _messages[idx] = _messages[idx].copyWith(
                  content: accumulated,
                  revealedChars: accumulated.length,
                );
              });
              _scrollToBottom();
            }
            break;

          case SseEventType.done:
            if (idx != -1) {
              setState(() {
                _messages[idx] = _messages[idx].copyWith(
                  content: accumulated,
                  isLoading: false,
                  isTyping: false,
                  revealedChars: accumulated.length,
                );
                _isLoading = false;
              });
            }
            if (event.metadata?['chat_title_updated'] == true) {
              await _loadChats();
            }
            break;

          case SseEventType.error:
            if (idx != -1) {
              setState(() {
                _messages[idx] = ChatMessage.error(
                  id: thinkingMsg.id,
                  content: _formatError(
                    event.error ?? 'Request gagal. Coba lagi.',
                    code: event.code,
                    requestId: event.requestId,
                  ),
                  timestamp: DateTime.now(),
                  errorCode: event.code,
                  requestId: event.requestId,
                );
                _isLoading = false;
              });
            }
            _showErrorSnack(event.error ?? 'Request gagal. Coba lagi.');
            break;
        }
      }

      // Ensure loading is cleared
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      final apiError = e is ApiException ? e : null;
      final errMsg = ChatMessage.error(
        id: thinkingMsg.id,
        content: _formatError(
          apiError?.message ?? e.toString(),
          code: apiError?.code,
          requestId: apiError?.requestId,
        ),
        timestamp: DateTime.now(),
        errorCode: apiError?.code,
        requestId: apiError?.requestId,
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
        if (idx != -1) _messages[idx] = errMsg;
        _isLoading = false;
      });
      _showErrorSnack(apiError?.supportMessage ?? e.toString());
    }
    _scrollToBottom();
  }

  void _handleFileAdded(PendingFile file) {
    setState(() => _pendingFiles.add(file));
  }

  void _removeAttachment(int index) {
    setState(() => _pendingFiles.removeAt(index));
  }

  void _clearAllAttachments() {
    setState(() => _pendingFiles.clear());
  }

  void _handleToolToggle(ChatTool tool) {
    if (tool == ChatTool.reasoning) {
      _handleReasoningToggle(!_reasoningEnabled);
      return;
    }

    setState(() {
      if (_activeTools.contains(tool)) {
        _activeTools.remove(tool);
      } else {
        _activeTools.add(tool);
      }
      // Auto-switch model for create_image
      if (tool == ChatTool.createImage && _activeTools.contains(tool)) {
        _currentModel = 'qc/qwen-image-2.0';
        _reasoningEnabled = false;
        _activeTools.remove(ChatTool.reasoning);
        if (_selectedChatId != null) {
          _api.updateChatModel(_selectedChatId!, _currentModel);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= AppConstants.sidebarBreakpoint;

    final sidebar = ChatSidebar(
      chats: _chats,
      selectedChatId: _selectedChatId,
      onChatSelected: _selectChat,
      onNewChat: _createNewChat,
      onRenameChat: _renameChat,
      onDeleteChat: _deleteChat,
      onLogout: widget.onLogout,
      username: _api.username ?? '',
    );

    final chatBody = Column(
      children: [
        if (_usageWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _usageWarning!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: _selectedChatId == null && _messages.isEmpty
              ? WelcomeView(onSuggestionTap: _sendMessage)
              : Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isDesktop
                          ? AppConstants.maxChatWidth
                          : double.infinity,
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 24 : 16,
                        vertical: 16,
                      ),
                      // Performance: add cache extent
                      cacheExtent: 500,
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final anim = _animControllers[msg.id];
                        // Wrap each message in RepaintBoundary to isolate repaints
                        return RepaintBoundary(
                          child: MessageBubble(
                            message: msg,
                            animation: anim,
                            onRetry: msg.isError ? _retryLastMessage : null,
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop
                  ? AppConstants.maxChatWidth + 48
                  : double.infinity,
            ),
            child: RepaintBoundary(
              child: ChatInput(
                onSend: _sendMessage,
                isLoading: _isLoading,
                onFileAdded: _handleFileAdded,
                attachedFiles: _pendingFiles,
                onRemoveAttachment: _removeAttachment,
                onClearAllAttachments: _clearAllAttachments,
                activeTools: _activeTools,
                onToolToggled: _handleToolToggle,
                supportsReasoning:
                    _currentModel == 'mk/sonnet-4.5' ||
                    _currentModel == 'mk/sonnet-4.5-thinking',
                currentModelSupportsVision: _models
                    .firstWhere(
                      (m) => m.id == _currentModel,
                      orElse: () => _models.first,
                    )
                    .supportsVision,
              ),
            ),
          ),
        ),
      ],
    );

    final appBar = AppBar(
      leading: isDesktop
          ? IconButton(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                  key: ValueKey(_sidebarOpen),
                  size: 22,
                ),
              ),
              onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
              tooltip: _sidebarOpen ? 'Tutup sidebar' : 'Buka sidebar',
            )
          : Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded, size: 22),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Row(
        children: [
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/logo.png', width: 28, height: 28),
          ),
          if (isDesktop) ...[
            const SizedBox(width: 10),
            Text(AppConstants.appName, style: theme.appBarTheme.titleTextStyle),
          ],
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ModelSelector(
            currentModel: _currentModel,
            models: _models,
            onModelChanged: (model) {
              setState(() {
                _currentModel = model;
                // Sync reasoning tool when model changes
                _reasoningEnabled = model == 'mk/sonnet-4.5-thinking';
                if (_reasoningEnabled) {
                  _activeTools.add(ChatTool.reasoning);
                } else {
                  _activeTools.remove(ChatTool.reasoning);
                }
              });
              // Persist model change to database for the active chat
              if (_selectedChatId != null) {
                ApiService().updateChatModel(_selectedChatId!, model);
              }
            },
          ),
        ),
        // Playground only on desktop (web-only feature)
        if (isDesktop) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PlaygroundScreen())),
            icon: const Icon(Icons.code_rounded, size: 20),
            tooltip: 'Playground',
          ),
        ],
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => AskCoreApp.of(context)?.toggleTheme(),
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            size: 20,
          ),
          tooltip: 'Toggle theme',
        ),
        const SizedBox(width: 4),
      ],
    );

    if (isDesktop) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _createNewChat,
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): () {
            setState(() => _sidebarOpen = !_sidebarOpen);
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  width: _sidebarOpen ? AppConstants.sidebarWidth : 0,
                  child: _sidebarOpen
                      ? AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: 1.0,
                          child: sidebar,
                        )
                      : const SizedBox.shrink(),
                ),
                if (_sidebarOpen)
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                Expanded(
                  child: Scaffold(appBar: appBar, body: chatBody),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(width: AppConstants.sidebarWidth, child: sidebar),
        body: chatBody,
      );
    }
  }
}
