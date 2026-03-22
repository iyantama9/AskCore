import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../core/constants.dart';
import '../services/api_service.dart';

/// Represents a pending file attachment (uploaded or pasted).
class PendingFile {
  final String url;
  final String name;
  const PendingFile({required this.url, required this.name});
}

class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool isLoading;
  final ValueChanged<PendingFile>? onFileAdded;
  final VoidCallback? onClearAllAttachments;
  final ValueChanged<int>? onRemoveAttachment;
  final List<PendingFile> attachedFiles;

  const ChatInput({
    super.key,
    required this.onSend,
    this.isLoading = false,
    this.onFileAdded,
    this.onClearAllAttachments,
    this.onRemoveAttachment,
    this.attachedFiles = const [],
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

  static const int maxFiles = 5;

  // Allowed extensions
  static const List<String> _allowedExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg',
    'dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'swift',
    'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'rb', 'php',
    'html', 'css', 'scss', 'sass', 'less',
    'json', 'yaml', 'yml', 'xml', 'toml', 'ini', 'env',
    'sql', 'sh', 'bash', 'bat', 'ps1', 'cmd',
    'md', 'txt', 'log', 'csv',
    'vue', 'svelte', 'astro',
    'r', 'lua', 'perl', 'scala', 'clj', 'ex', 'exs', 'erl',
    'dockerfile', 'makefile', 'cmake',
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

  bool get _canAddMore => widget.attachedFiles.length < maxFiles;

  /// Upload raw bytes (from clipboard or file picker)
  Future<void> _uploadBytes(Uint8List bytes, String fileName, String contentType) async {
    if (!_canAddMore) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 5 file per pesan')),
        );
      }
      return;
    }

    if (bytes.length > AppConstants.maxFileSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File terlalu besar (maks 1MB)')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    try {
      final uploadResult = await ApiService().uploadFile(bytes, fileName, contentType);
      widget.onFileAdded?.call(PendingFile(
        url: uploadResult['url'] ?? '',
        name: uploadResult['name'] ?? fileName,
      ));
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

  /// Handle clipboard paste (Ctrl+V / Cmd+V)
  Future<void> _handlePaste() async {
    try {
      final data = await Clipboard.getData('text/plain');
      // On web, check for image data from clipboard API
      if (kIsWeb) {
        // Use the HTML paste event approach via the Focus widget below
        return;
      }
      // On mobile/desktop, clipboard images are not directly accessible
      // via Clipboard.getData. Users can use file picker instead.
      if (data?.text != null) {
        // Let the text field handle text paste normally
        return;
      }
    } catch (_) {}
  }

  /// Handle pasted image bytes (from web clipboard event)
  Future<void> handlePastedImage(Uint8List bytes, String mimeType) async {
    final ext = mimeType.split('/').last;
    final fileName = 'pasted_image_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _uploadBytes(bytes, fileName, mimeType);
  }

  Future<void> _pickFile() async {
    if (_isUploading || widget.isLoading || !_canAddMore) {
      if (!_canAddMore && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 5 file per pesan')),
        );
      }
      return;
    }

    final remaining = maxFiles - widget.attachedFiles.length;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
      allowMultiple: remaining > 1,
    );

    if (result == null || result.files.isEmpty) return;

    // Take only up to remaining slots
    final files = result.files.take(remaining).toList();

    for (final file in files) {
      if (file.bytes == null) continue;

      if (file.size > AppConstants.maxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name} terlalu besar (maks 1MB)')),
          );
        }
        continue;
      }

      final ext = file.extension?.toLowerCase() ?? '';
      String contentType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(ext)) contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'gif') contentType = 'image/gif';
      if (ext == 'webp') contentType = 'image/webp';
      if (ext == 'pdf') contentType = 'application/pdf';
      if (ext == 'ppt' || ext == 'pptx') contentType = 'application/vnd.ms-powerpoint';
      if (ext == 'svg') contentType = 'image/svg+xml';
      if (['txt', 'md', 'log', 'csv'].contains(ext)) contentType = 'text/plain';

      await _uploadBytes(file.bytes!, file.name, contentType);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAttachments = widget.attachedFiles.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Attached files chips
            if (hasAttachments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (int i = 0; i < widget.attachedFiles.length; i++)
                      _buildFileChip(theme, widget.attachedFiles[i], i),
                  ],
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
                        // Attach button
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
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  )
                                : Badge(
                                    isLabelVisible: hasAttachments,
                                    label: Text('${widget.attachedFiles.length}'),
                                    child: Icon(
                                      Icons.add_rounded,
                                      size: 22,
                                      color: hasAttachments
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                            tooltip: _canAddMore
                                ? 'Attach file (${widget.attachedFiles.length}/$maxFiles)'
                                : 'Maksimal $maxFiles file',
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

  Widget _buildFileChip(ThemeData theme, PendingFile file, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getFileIcon(file.name),
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              file.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => widget.onRemoveAttachment?.call(index),
            borderRadius: BorderRadius.circular(10),
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
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
