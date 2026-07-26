import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import '../helpers/artifact_download.dart';
import '../models/artifact_model.dart';
import '../services/api_service.dart';

class ArtifactViewer extends StatefulWidget {
  final ChatArtifact artifact;
  final VoidCallback onClose;

  const ArtifactViewer({
    super.key,
    required this.artifact,
    required this.onClose,
  });

  @override
  State<ArtifactViewer> createState() => _ArtifactViewerState();
}

class _ArtifactViewerState extends State<ArtifactViewer> {
  String? _selectedPath;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.artifact.firstFile?.path;
  }

  @override
  void didUpdateWidget(covariant ArtifactViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artifact.id != widget.artifact.id) {
      _selectedPath = widget.artifact.firstFile?.path;
      _copied = false;
    }
  }

  ArtifactFile? get _selectedFile {
    if (widget.artifact.files.isEmpty) return null;
    return widget.artifact.files.firstWhere(
      (file) => file.path == _selectedPath,
      orElse: () => widget.artifact.files.first,
    );
  }

  Future<void> _copySelectedFile() async {
    final file = _selectedFile;
    if (file == null) return;
    await Clipboard.setData(ClipboardData(text: file.content));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Triggers a browser download via a temporary object URL. package:web
  /// keeps this compatible with both dart2js and dart2wasm builds.
  void _saveBytesAsFile(Uint8List bytes, String filename) {
    downloadFileAsBytes(bytes, filename);
  }

  Future<void> _downloadFile(String artifactId, String filePath) async {
    try {
      final response = await ApiService().downloadArtifactFile(artifactId, filePath);

      if (response.statusCode == 401) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please login again.')),
          );
        }
        return;
      }

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download gagal (${response.statusCode})')),
          );
        }
        return;
      }

      final bytes = response.bodyBytes;
      final filename = filePath.split('/').last;

      if (kIsWeb) {
        _saveBytesAsFile(bytes, filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    }
  }

  Future<void> _downloadZip(String artifactId) async {
    try {
      final response = await ApiService().downloadArtifactZip(artifactId);

      if (response.statusCode == 401) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please login again.')),
          );
        }
        return;
      }

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download gagal (${response.statusCode})')),
          );
        }
        return;
      }

      final bytes = response.bodyBytes;
      final filename = '${widget.artifact.title}.zip';

      if (kIsWeb) {
        _saveBytesAsFile(bytes, filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final file = _selectedFile;

    return Material(
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          _ArtifactTitleBar(
            artifact: widget.artifact,
            onClose: widget.onClose,
            onDownloadZip: widget.artifact.files.length > 1
                ? () => _downloadZip(widget.artifact.id)
                : null,
          ),
          if (widget.artifact.files.isNotEmpty)
            _FileTabs(
              files: widget.artifact.files,
              selectedPath: file?.path,
              onSelected: (path) => setState(() => _selectedPath = path),
            ),
          Expanded(
            child: isMobile
                ? Column(
                    children: [
                      _MobileFileSelector(
                        files: widget.artifact.files,
                        selectedPath: file?.path,
                        onSelected: (path) => setState(() => _selectedPath = path),
                      ),
                      Expanded(child: _EditorArea(file: file)),
                    ],
                  )
                : Row(
                    children: [
                      _FileTree(
                        files: widget.artifact.files,
                        selectedPath: file?.path,
                        onSelected: (path) => setState(() => _selectedPath = path),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      Expanded(child: _EditorArea(file: file)),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1020),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file == null
                        ? 'Tidak ada file'
                        : '${file.path} • ${_formatBytes(file.size)} • read-only',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                _EditorButton(
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  label: _copied ? 'Copied' : 'Copy',
                  onTap: file == null ? null : _copySelectedFile,
                  color: _copied ? const Color(0xFF22C55E) : null,
                ),
                const SizedBox(width: 8),
                _EditorButton(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  onTap: file == null
                      ? null
                      : () => _downloadFile(widget.artifact.id, file.path),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ArtifactTitleBar extends StatelessWidget {
  final ChatArtifact artifact;
  final VoidCallback onClose;
  final VoidCallback? onDownloadZip;

  const _ArtifactTitleBar({
    required this.artifact,
    required this.onClose,
    this.onDownloadZip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          const Icon(Icons.data_object_rounded, size: 18, color: Color(0xFF60A5FA)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              artifact.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${artifact.fileCount} file',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onDownloadZip != null) ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: onDownloadZip,
              icon: const Icon(Icons.archive_rounded, size: 18),
              color: Colors.white70,
              tooltip: 'Download ZIP',
            ),
          ],
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: Colors.white70,
            tooltip: 'Tutup artifact',
          ),
        ],
      ),
    );
  }
}

class _FileTabs extends StatelessWidget {
  final List<ArtifactFile> files;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  const _FileTabs({
    required this.files,
    required this.selectedPath,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: const Color(0xFF0F172A),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, __) => Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),
        itemBuilder: (context, index) {
          final file = files[index];
          final selected = file.path == selectedPath;
          return InkWell(
            onTap: () => onSelected(file.path),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF1E293B) : Colors.transparent,
                border: selected
                    ? const Border(top: BorderSide(color: Color(0xFF60A5FA), width: 2))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconForFile(file), size: 15, color: selected ? Colors.white : Colors.white60),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white60,
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FileTree extends StatelessWidget {
  final List<ArtifactFile> files;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  const _FileTree({
    required this.files,
    required this.selectedPath,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Container(
        color: const Color(0xFF0B1020),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Text(
                'EXPLORER',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final selected = file.path == selectedPath;
                  final depth = file.path.split('/').length - 1;
                  final indent = depth < 0 ? 0 : depth > 3 ? 3 : depth;
                  return InkWell(
                    onTap: () => onSelected(file.path),
                    child: Container(
                      padding: EdgeInsets.only(
                        left: 12 + indent * 10,
                        right: 8,
                        top: 7,
                        bottom: 7,
                      ),
                      color: selected
                          ? const Color(0xFF1E293B)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          Icon(
                            _iconForFile(file),
                            size: 15,
                            color: selected
                                ? const Color(0xFF93C5FD)
                                : Colors.white54,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              file.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileFileSelector extends StatelessWidget {
  final List<ArtifactFile> files;
  final String? selectedPath;
  final ValueChanged<String> onSelected;

  const _MobileFileSelector({
    required this.files,
    required this.selectedPath,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (files.length <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: const Color(0xFF0B1020),
      child: DropdownButtonFormField<String>(
        initialValue: selectedPath,
        dropdownColor: const Color(0xFF111827),
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: files
            .map(
              (file) => DropdownMenuItem(
                value: file.path,
                child: Text(file.path, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onSelected(value);
        },
      ),
    );
  }
}

class _EditorArea extends StatelessWidget {
  final ArtifactFile? file;

  const _EditorArea({required this.file});

  @override
  Widget build(BuildContext context) {
    final selected = file;
    if (selected == null) {
      return const Center(
        child: Text('Tidak ada file', style: TextStyle(color: Colors.white54)),
      );
    }

    final language = _normalizeLanguage(selected.language);
    final lineCount = selected.content.isEmpty
        ? 1
        : selected.content.split('\n').length;
    final rawGutterWidth = lineCount.toString().length * 10.0;
    final gutterWidth = rawGutterWidth < 38.0
        ? 38.0
        : rawGutterWidth > 62.0
        ? 62.0
        : rawGutterWidth;

    return Container(
      color: const Color(0xFF0D1117),
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: gutterWidth,
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
                color: const Color(0xFF0B1020),
                child: Text(
                  List.generate(lineCount, (index) => '${index + 1}').join('\n'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.28),
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.52,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: HighlightView(
                  selected.content,
                  language: language,
                  theme: monokaiSublimeTheme,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.52,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _EditorButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Colors.white70;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: effectiveColor),
      label: Text(label, style: TextStyle(color: effectiveColor, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}

IconData _iconForFile(ArtifactFile file) {
  final ext = file.name.split('.').last.toLowerCase();
  if (['dart', 'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'go', 'rs'].contains(ext)) {
    return Icons.code_rounded;
  }
  if (['md', 'txt', 'log'].contains(ext)) return Icons.notes_rounded;
  if (ext == 'csv') return Icons.table_chart_rounded;
  if (ext == 'json') return Icons.data_object_rounded;
  return Icons.insert_drive_file_rounded;
}

String _normalizeLanguage(String lang) {
  final lower = lang.toLowerCase();
  const aliases = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'kt': 'kotlin',
    'rs': 'rust',
    'sh': 'bash',
    'md': 'markdown',
    'txt': 'plaintext',
    'text': 'plaintext',
  };
  return aliases[lower] ?? lower;
}
