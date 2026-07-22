import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../models/message_model.dart';

String normalizeMathMarkdown(String markdown) {
  return markdown.replaceAllMapped(RegExp(r'```[ \t]*\n([\s\S]*?)\n```'), (
    match,
  ) {
    final content = match.group(1)?.trim() ?? '';
    if (!_looksLikeFormulaBlock(content)) return match.group(0)!;
    return '\$\$\n$content\n\$\$';
  });
}

bool _looksLikeFormulaBlock(String content) {
  if (content.isEmpty || content.contains(';')) return false;

  final lines = content
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty || lines.length > 4) return false;

  final formulaSignals = RegExp(
    r'(\\(?:frac|sqrt|sum|prod|int|lim|sin|cos|tan|ln|log|times|cdot|mod|pm|leq|geq)|[=^_∑√π×÷±≤≥]|\b(?:mod|sin|cos|ln|log)\b)',
  );
  final proseSignals = RegExp(
    r'^(-|\*|\d+\.|for\s|if\s|while\s|return\s)',
    caseSensitive: false,
  );

  return lines.every(
    (line) => formulaSignals.hasMatch(line) && !proseSignals.hasMatch(line),
  );
}

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final Animation<double>? animation;
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    this.animation,
    this.onRetry,
  });

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

  Widget _buildMessageAction(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: effectiveColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
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
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
                      child: Image.asset(
                        'assets/logo.png',
                        width: 16,
                        height: 16,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.person_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
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
              color: msg.isError
                  ? theme.colorScheme.errorContainer.withValues(alpha: 0.35)
                  : isUser
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              border: Border.all(
                color: msg.isError
                    ? theme.colorScheme.error.withValues(alpha: 0.35)
                    : isUser
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
                    '${msg.displayContent}▌',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      height: 1.6,
                    ),
                  )
                : MarkdownBody(
                    data: normalizeMathMarkdown(msg.displayContent),
                    selectable: true,
                    styleSheet: _markdownStyle(theme),
                    extensionSet: md.ExtensionSet(
                      [
                        LatexBlockSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
                      ],
                      [
                        LatexInlineSyntax(),
                        ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
                      ],
                    ),
                    builders: {
                      'pre': _CodeBlockBuilder(),
                      'latex': LatexElementBuilder(
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    },
                    onTapLink: (text, href, title) => _openSafeLink(href),
                    sizedImageBuilder: (config) => _buildImage(
                      config.uri,
                      config.title,
                      config.alt,
                      theme,
                    ),
                  ),
          ),
          if (!isUser && isDone && msg.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Wrap(
                spacing: 4,
                children: [
                  _buildMessageAction(
                    theme,
                    icon: _showCopied
                        ? Icons.check_rounded
                        : Icons.copy_rounded,
                    label: _showCopied ? 'Copied!' : 'Copy',
                    color: _showCopied ? Colors.green : null,
                    onTap: _copyContent,
                  ),
                  if (msg.isError && widget.onRetry != null)
                    _buildMessageAction(
                      theme,
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      color: theme.colorScheme.primary,
                      onTap: widget.onRetry!,
                    ),
                ],
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

  bool _isSafeHttpUrl(Uri uri) {
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  bool _isTrustedImageUri(Uri uri) {
    if (uri.scheme == 'data') {
      return uri.toString().toLowerCase().startsWith('data:image/');
    }
    if (!_isSafeHttpUrl(uri)) return false;
    final host = uri.host.toLowerCase();
    return host == 'askcore.dev' || host == 'www.askcore.dev';
  }

  Future<void> _openSafeLink(String? href) async {
    if (href == null || href.trim().isEmpty) return;
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !_isSafeHttpUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildBlockedImage(ThemeData theme) {
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Text(
          'Gambar eksternal diblokir',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenImage(ThemeData theme) {
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
            Icon(Icons.broken_image_rounded, color: theme.colorScheme.error),
            const SizedBox(height: 4),
            Text('Gagal memuat gambar', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(String imageUrl, Uri safeUri, ThemeData theme) {
    if (safeUri.scheme == 'data') {
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            UriData.parse(imageUrl).contentAsBytes(),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _buildBrokenImage(theme),
          ),
        );
      } catch (_) {
        return _buildBrokenImage(theme);
      }
    }

    return ClipRRect(
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
        errorBuilder: (context, error, stack) => _buildBrokenImage(theme),
      ),
    );
  }

  Widget _buildImage(Uri uri, String? title, String? alt, ThemeData theme) {
    // Rewrite localhost URLs for mobile compatibility
    String imageUrl = uri.toString();
    imageUrl = imageUrl.replaceFirst(
      RegExp(r'http://localhost:\d+'),
      AppConstants.backendUrl,
    );

    final safeUri = Uri.tryParse(imageUrl);
    if (safeUri == null || !_isTrustedImageUri(safeUri)) {
      return _buildBlockedImage(theme);
    }

    final canOpenDownload = _isSafeHttpUrl(safeUri);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Stack(
        children: [
          _buildImageContent(imageUrl, safeUri, theme),
          if (canOpenDownload)
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openSafeLink(imageUrl),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
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
      h1: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      listBullet: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
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
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
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
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
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
