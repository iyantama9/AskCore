import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  final List<ModelInfo> _models = ChatService.allModels;
  int? _selectedChatId;
  String _currentModel = AppConstants.defaultModel;
  bool _isLoading = false;
  bool _sidebarOpen = true;
  Timer? _typewriterTimer;

  // Only animate the LATEST 2 messages (user + assistant)
  final Map<String, AnimationController> _animControllers = {};

  // File attachments (up to 5)
  List<PendingFile> _pendingFiles = [];

  // Active tools
  Set<ChatTool> _activeTools = {};

  // Track the typing message index for scoped rebuilds
  int? _typingIndex;

  @override
  void initState() {
    super.initState();
    _loadChats();
    // Setup web clipboard paste listener for images
    setupWebPasteListener(_onImagePasted);
  }

  Future<void> _onImagePasted(Uint8List bytes, String mimeType) async {
    if (_pendingFiles.length >= 5) return;
    final ext = mimeType.split('/').last;
    final fileName = 'pasted_${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      final result = await _api.uploadFile(bytes, fileName, mimeType);
      if (mounted) {
        setState(() {
          _pendingFiles.add(PendingFile(
            url: result['key'] ?? '',
            name: result['file_name'] ?? fileName,
          ));
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    disposeWebPasteListener();
    _scrollController.dispose();
    _typewriterTimer?.cancel();
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
    _typewriterTimer?.cancel();
    _typingIndex = null;
    _cleanupAnimControllers();

    try {
      final msgs = await _api.getMessages(chatId);
      if (mounted) {
        setState(() {
          _messages = msgs
              .map((m) => ChatMessage(
                    id: m['id'].toString(),
                    role: m['role'] == 'user'
                        ? MessageRole.user
                        : MessageRole.assistant,
                    content: m['content'] ?? '',
                    timestamp: DateTime.tryParse(m['created_at'] ?? '') ??
                        DateTime.now(),
                  ))
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

  void _startTypewriter(int index, String fullContent) {
    _typewriterTimer?.cancel();
    int currentChar = 0;
    final totalChars = fullContent.length;
    int scrollCooldown = 0;

    _typewriterTimer =
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Faster reveal: bigger chunks
      final speed = (currentChar < 50) ? 3 : (currentChar < 200) ? 6 : 12;
      currentChar = (currentChar + speed).clamp(0, totalChars);

      setState(() {
        _messages[index] = _messages[index].copyWith(
          revealedChars: currentChar,
        );
      });

      // Scroll every ~5 ticks instead of every tick
      scrollCooldown++;
      if (scrollCooldown >= 5) {
        scrollCooldown = 0;
        _scrollToBottom();
      }

      if (currentChar >= totalChars) {
        timer.cancel();
        setState(() {
          _messages[index] = _messages[index].copyWith(
            isTyping: false,
            isLoading: false,
            revealedChars: totalChars,
          );
          _typingIndex = null;
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _selectChat(int chatId) async {
    setState(() => _selectedChatId = chatId);
    await _loadMessages(chatId);
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

  Future<void> _sendMessage(String content) async {
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

    String userContent = content;
    if (_pendingFiles.isNotEmpty) {
      final names = _pendingFiles.map((f) => '📎 ${f.name}').join('\n');
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

    try {
      final result = await _api.sendMessage(
        _selectedChatId!,
        content,
        files: _pendingFiles,
        tools: _activeTools.map((t) => t == ChatTool.browseWeb ? 'browse_web' : 'create_image').toList(),
      );

      final aiContent = result['message']?['content'] ?? 'No response';

      final aiMsg = ChatMessage(
        id: thinkingMsg.id,
        role: MessageRole.assistant,
        content: aiContent,
        timestamp: DateTime.now(),
        isLoading: true,
        isThinking: false,
        isTyping: true,
        revealedChars: 0,
      );

      final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
      if (idx != -1) {
        setState(() {
          _messages[idx] = aiMsg;
          _isLoading = false;
          _pendingFiles = [];
          _typingIndex = idx;
        });
        _startTypewriter(idx, aiContent);
      }

      if (result['chat_title_updated'] == true) {
        await _loadChats();
      }
    } catch (e) {
      final errMsg = ChatMessage(
        id: thinkingMsg.id,
        role: MessageRole.assistant,
        content: '⚠️ $e',
        timestamp: DateTime.now(),
      );
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == thinkingMsg.id);
        if (idx != -1) _messages[idx] = errMsg;
        _isLoading = false;
      });
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
    setState(() {
      if (_activeTools.contains(tool)) {
        _activeTools.remove(tool);
      } else {
        _activeTools.add(tool);
      }
      // Auto-switch model for create_image
      if (tool == ChatTool.createImage && _activeTools.contains(tool)) {
        _currentModel = 'gemini-2.0-flash-preview-image-generation';
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
                          child: MessageBubble(message: msg, animation: anim),
                        );
                      },
                    ),
                  ),
                ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  isDesktop ? AppConstants.maxChatWidth + 48 : double.infinity,
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
                  _sidebarOpen
                      ? Icons.menu_open_rounded
                      : Icons.menu_rounded,
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
              setState(() => _currentModel = model);
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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlaygroundScreen()),
            ),
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
      return Scaffold(
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
