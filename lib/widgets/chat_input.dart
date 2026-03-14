import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants.dart';
import '../services/api_service.dart';

class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool isLoading;
  final ValueChanged<Map<String, dynamic>>? onFileUploaded;
  final String? attachedFileName;
  final VoidCallback? onClearAttachment;

  const ChatInput({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onFileUploaded,
    this.attachedFileName,
    this.onClearAttachment,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late AnimationController _sendButtonAnimController;
  bool _hasText = false;
  bool _isUploading = false;

  // Allowed extensions
  static const List<String> _allowedExtensions = [
    // Images
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg',
    // Code files
    'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'swift',
    'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'rb', 'php',
    'html', 'css', 'scss', 'sass', 'less',
    'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'env',
    'sql', 'sh', 'bash', 'bat', 'ps1', 'cmd',
    'md', 'txt', 'log', 'csv',
    'vue', 'svelte', 'astro',
    'r', 'lua', 'perl', 'scala', 'clj', 'ex', 'exs', 'erl',
    'dockerfile', 'makefile', 'cmake',
    // Documents
    'pdf', 'ppt', 'pptx',
  ];

  @override
  void initState() {
    super.initState();
    _sendButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
        hasText
            ? _sendButtonAnimController.forward()
            : _sendButtonAnimController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _sendButtonAnimController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _pickFile() async {
    if (_isUploading || widget.isLoading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    if (file.bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File tidak bisa dibaca')),
        );
      }
      return;
    }

    if (file.size > AppConstants.maxFileSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File terlalu besar (maks 1MB)')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    try {
      final ext = file.extension?.toLowerCase() ?? '';
      String contentType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(ext)) contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'gif') contentType = 'image/gif';
      if (ext == 'webp') contentType = 'image/webp';
      if (ext == 'pdf') contentType = 'application/pdf';
      if (ext == 'ppt' || ext == 'pptx') {
        contentType = 'application/vnd.ms-powerpoint';
      }
      if (ext == 'svg') contentType = 'image/svg+xml';
      if (ext == 'txt' || ext == 'md' || ext == 'log' || ext == 'csv') {
        contentType = 'text/plain';
      }

      final uploadResult = await ApiService().uploadFile(
        file.bytes!,
        file.name,
        contentType,
      );

      widget.onFileUploaded?.call(uploadResult);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAttachment = widget.attachedFileName != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attached file chip
            if (hasAttachment)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getFileIcon(widget.attachedFileName!),
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.attachedFileName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: widget.onClearAttachment,
                        borderRadius: BorderRadius.circular(12),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.inputDecorationTheme.fillColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Attach button inside the input
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: IconButton(
                            onPressed: _isUploading ? null : _pickFile,
                            icon: _isUploading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Icon(
                                    Icons.add_rounded,
                                    size: 22,
                                    color: hasAttachment
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                            tooltip: 'Attach file',
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                _handleSend();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              maxLines: 5,
                              minLines: 1,
                              textInputAction: TextInputAction.newline,
                              style: theme.textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText: widget.isLoading
                                    ? 'Menunggu respons...'
                                    : 'Tanya apa saja...',
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                fillColor: Colors.transparent,
                                filled: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Send button
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              gradient: _hasText && !widget.isLoading
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF7C3AED),
                                        Color(0xFF9333EA),
                                      ],
                                    )
                                  : null,
                              color: _hasText && !widget.isLoading
                                  ? null
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              onPressed: _hasText && !widget.isLoading
                                  ? _handleSend
                                  : null,
                              icon: widget.isLoading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Icon(
                                      Icons.arrow_upward_rounded,
                                      size: 20,
                                      color: _hasText
                                          ? Colors.white
                                          : theme
                                              .colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.4),
                                    ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg']
        .contains(ext)) {
      return Icons.image_rounded;
    }
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    return Icons.code_rounded;
  }
}
