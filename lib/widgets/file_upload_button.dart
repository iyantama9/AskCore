import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants.dart';
import '../services/api_service.dart';

class FileUploadButton extends StatelessWidget {
  final ValueChanged<Map<String, dynamic>> onFileUploaded;
  final bool isLoading;

  const FileUploadButton({
    super.key,
    required this.onFileUploaded,
    this.isLoading = false,
  });

  Future<void> _pickAndUpload(BuildContext context) async {
    final theme = Theme.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'pdf', 'doc', 'docx', 'txt'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    if (file.bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read file')),
        );
      }
      return;
    }

    if (file.size > AppConstants.maxFileSize) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File terlalu besar (maks 1MB)')),
        );
      }
      return;
    }

    try {
      final ext = file.extension?.toLowerCase() ?? '';
      String contentType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(ext)) contentType = 'image/jpeg';
      if (ext == 'png') contentType = 'image/png';
      if (ext == 'gif') contentType = 'image/gif';
      if (ext == 'pdf') contentType = 'application/pdf';
      if (ext == 'txt') contentType = 'text/plain';

      final uploadResult = await ApiService().uploadFile(
        file.bytes!,
        file.name,
        contentType,
      );

      onFileUploaded(uploadResult);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload gagal: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: isLoading ? null : () => _pickAndUpload(context),
      icon: Icon(
        Icons.attach_file_rounded,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Upload file (maks 1MB)',
    );
  }
}
