import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../models/message_model.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final Animation<double>? animation;

  const MessageBubble({super.key, required this.message, this.animation});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _showCopied = false;

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    setState(() => _showCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final isUser = msg.role == MessageRole.user;
    final isThinking = msg.isThinking;
    final isTyping = msg.isTyping;
    final isDone = !msg.isLoading && !isThinking && !isTyping;

    Widget bubble = Container(
      margin: EdgeInsets.only(
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Role label
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset('assets/logo.png',
                          width: 16, height: 16),
                    ),
                  )
                else
                  Icon(Icons.person_rounded,
                      size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  isUser ? 'You' : 'AskCore',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Message body
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border: Border.all(
                color: isUser
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: isThinking
                ? _buildThinkingIndicator(theme)
                : isUser
                    ? SelectableText(
                        msg.content,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          height: 1.5,
                        ),
                      )
                    // Performance: use plain Text during typing, 
                    // full Markdown only when display is complete
                    : isTyping
                        ? Text(
                            msg.displayContent + '▌',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.6,
                            ),
                          )
                        : MarkdownBody(
                            data: msg.displayContent,
                            selectable: true,
                            styleSheet: _markdownStyle(theme),
                            builders: {
                              'pre': _CodeBlockBuilder(),
                            },
                            imageBuilder: (uri, title, alt) =>
                                _buildImage(uri, title, alt, theme),
                          ),
          ),
          // Copy button
          if (!isUser && isDone && msg.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: InkWell(
                onTap: _copyContent,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showCopied
                            ? Icons.check_rounded
                            : Icons.copy_rounded,
                        size: 14,
                        color: _showCopied
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _showCopied ? 'Copied!' : 'Copy',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _showCopied
                              ? Colors.green
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.animation != null) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: widget.animation!,
          curve: Curves.easeOut,
        ),
        child: bubble,
      );
    }

    return bubble;
  }

  Widget _buildImage(Uri uri, String? title, String? alt, ThemeData theme) {
    // Rewrite localhost URLs for mobile compatibility
    String imageUrl = uri.toString();
    imageUrl = imageUrl.replaceFirst(
      RegExp(r'http://localhost:\d+'),
      AppConstants.backendUrl,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stack) {
                return Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_rounded,
                            color: theme.colorScheme.error),
                        const SizedBox(height: 4),
                        Text('Gagal memuat gambar',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Download button
          Positioned(
            right: 8,
            bottom: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.download_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ThemeData theme) {
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.6,
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: const Color(0xFF1E1E2E),
        color: const Color(0xFFE06C75),
        fontSize: 13,
      ),
      codeblockDecoration: const BoxDecoration(),
      codeblockPadding: EdgeInsets.zero,
      h1: theme.textTheme.titleLarge
          ?.copyWith(color: theme.colorScheme.onSurface),
      h2: theme.textTheme.titleMedium
          ?.copyWith(color: theme.colorScheme.onSurface),
      h3: theme.textTheme.titleSmall
          ?.copyWith(color: theme.colorScheme.onSurface),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      listBullet: theme.textTheme.bodyMedium
          ?.copyWith(color: theme.colorScheme.onSurface),
      strong: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
      em: theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurface,
      ),
      a: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      // Table fixes: prevent columns from collapsing
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outline.withValues(alpha: 0.3),
        width: 0.5,
        borderRadius: BorderRadius.circular(4),
      ),
      tableHead: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface,
      ),
      tableBody: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Thinking...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Custom code block builder with syntax highlighting and copy button
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Extract language and code
    String code = element.textContent;
    String language = '';

    if (element.children != null && element.children!.isNotEmpty) {
      final first = element.children!.first;
      if (first is md.Element && first.tag == 'code') {
        final cls = first.attributes['class'] ?? '';
        if (cls.startsWith('language-')) {
          language = cls.replaceFirst('language-', '');
        }
        code = first.textContent;
      }
    }

    // Remove trailing newline
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);

    return _CodeBlockWidget(code: code, language: language);
  }
}

class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;

  const _CodeBlockWidget({required this.code, required this.language});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  // Map common language aliases
  String _normalizeLanguage(String lang) {
    final map = {
      'js': 'javascript',
      'ts': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'kt': 'kotlin',
      'rs': 'rust',
      'sh': 'bash',
      'yml': 'yaml',
      'md': 'markdown',
      'cs': 'csharp',
      'cpp': 'cpp',
      'tsx': 'typescript',
      'jsx': 'javascript',
    };
    return map[lang.toLowerCase()] ?? lang.toLowerCase();
  }

  String _displayLanguage(String lang) {
    if (lang.isEmpty) return 'code';
    final display = {
      'javascript': 'JavaScript',
      'typescript': 'TypeScript',
      'python': 'Python',
      'dart': 'Dart',
      'html': 'HTML',
      'css': 'CSS',
      'json': 'JSON',
      'yaml': 'YAML',
      'bash': 'Bash',
      'shell': 'Shell',
      'sql': 'SQL',
      'rust': 'Rust',
      'go': 'Go',
      'java': 'Java',
      'kotlin': 'Kotlin',
      'swift': 'Swift',
      'csharp': 'C#',
      'cpp': 'C++',
      'c': 'C',
      'php': 'PHP',
      'ruby': 'Ruby',
      'markdown': 'Markdown',
      'xml': 'XML',
      'dockerfile': 'Dockerfile',
    };
    final norm = _normalizeLanguage(lang);
    return display[norm] ?? lang.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedLang = _normalizeLanguage(widget.language);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final codeFontSize = isMobile ? 11.5 : 13.0;
    final codePadding = isMobile ? 10.0 : 14.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 14,
              vertical: isMobile ? 6 : 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF12121E),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // Language dot
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _getLanguageColor(normalizedLang),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _displayLanguage(widget.language),
                  style: TextStyle(
                    color: const Color(0xFF8B8FA7),
                    fontSize: isMobile ? 10.5 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                // Copy button
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 6 : 8,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied
                              ? Icons.check_rounded
                              : Icons.copy_rounded,
                          size: isMobile ? 12 : 14,
                          color: _copied
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF8B8FA7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied!' : 'Copy',
                          style: TextStyle(
                            fontSize: isMobile ? 10.5 : 12,
                            color: _copied
                                ? const Color(0xFF22C55E)
                                : const Color(0xFF8B8FA7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code body with syntax highlighting
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: EdgeInsets.all(codePadding),
              child: HighlightView(
                widget.code,
                language: normalizedLang.isEmpty ? 'plaintext' : normalizedLang,
                theme: monokaiSublimeTheme,
                padding: EdgeInsets.zero,
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: codeFontSize,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLanguageColor(String lang) {
    final colors = {
      'javascript': const Color(0xFFF7DF1E),
      'typescript': const Color(0xFF3178C6),
      'python': const Color(0xFF3776AB),
      'dart': const Color(0xFF0175C2),
      'html': const Color(0xFFE34F26),
      'css': const Color(0xFF1572B6),
      'json': const Color(0xFF292929),
      'rust': const Color(0xFFDEA584),
      'go': const Color(0xFF00ADD8),
      'java': const Color(0xFFB07219),
      'kotlin': const Color(0xFF7F52FF),
      'swift': const Color(0xFFFA7343),
      'csharp': const Color(0xFF178600),
      'cpp': const Color(0xFFF34B7D),
      'ruby': const Color(0xFFCC342D),
      'php': const Color(0xFF777BB4),
      'bash': const Color(0xFF4EAA25),
      'sql': const Color(0xFFE38C00),
    };
    return colors[lang] ?? const Color(0xFF8B8FA7);
  }
}
