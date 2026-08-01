import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';

class RouterConfigScreen extends StatefulWidget {
  const RouterConfigScreen({super.key});

  @override
  State<RouterConfigScreen> createState() => _RouterConfigScreenState();
}

class _RouterConfigScreenState extends State<RouterConfigScreen> {
  List<dynamic> _configs = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _error;
  late AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(ApiService().token ?? '');
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final configs = await _adminService.getRouterConfigs();
      setState(() {
        _configs = configs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _syncModels() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _adminService.syncModelsFromRouter();
      if (!mounted) return;
      final count = result['count'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Berhasil sync $count model dari router'),
          backgroundColor: Colors.green[700],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Gagal sync model: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _testConnection(int id, String name) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    try {
      final result = await _adminService.testRouterConnection(id);
      if (mounted) {
        Navigator.pop(context);

        final success = result['success'] == true;
        final duration = result['duration_ms'];

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error,
                  color: success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(success ? 'Connection Successful' : 'Connection Failed'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Router: $name'),
                if (duration != null) Text('Response time: ${duration}ms'),
                if (result['message'] != null)
                  Text('Message: ${result['message']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    }
  }

  Future<void> _saveConfig({
    Map<String, dynamic>? existing,
    required String name,
    required String baseUrl,
    required String apiKey,
    required int timeoutMs,
    required int maxRetries,
  }) async {
    try {
      if (existing != null) {
        await _adminService.updateRouterConfig(existing['id'], {
          'name': name,
          'base_url': baseUrl,
          'api_key': apiKey,
          'timeout_ms': timeoutMs,
          'max_retries': maxRetries,
        });
      } else {
        await _adminService.createRouterConfig({
          'name': name,
          'base_url': baseUrl,
          'api_key': apiKey,
          'timeout_ms': timeoutMs,
          'max_retries': maxRetries,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null
                ? '✅ Router berhasil diupdate'
                : '✅ Router berhasil ditambahkan'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
      await _loadConfigs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal menyimpan: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteConfig(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Router'),
        content: Text('Yakin ingin menghapus router "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminService.deleteRouterConfig(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Router "$name" berhasil dihapus'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
      await _loadConfigs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal menghapus: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Router Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfigs,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: _isSyncing ? null : _syncModels,
            icon: _isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(_isSyncing ? 'Syncing...' : 'Sync Models'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _showConfigDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Router'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 48, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadConfigs,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildConfigList(),
    );
  }

  Widget _buildConfigList() {
    final theme = Theme.of(context);

    if (_configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.router, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No router configurations found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showConfigDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Router'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _configs.length,
      itemBuilder: (context, index) {
        final config = _configs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                config['name'],
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (config['is_active'] == true)
                                Chip(
                                  label: const Text('Active'),
                                  backgroundColor: Colors.green.withValues(alpha: 0.2),
                                  labelStyle: TextStyle(color: Colors.green[700]),
                                )
                              else
                                Chip(
                                  label: const Text('Inactive'),
                                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            config['base_url'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _testConnection(
                            config['id'],
                            config['name'],
                          ),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Test'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showConfigDialog(config: config),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: theme.colorScheme.error),
                          onPressed: () =>
                              _deleteConfig(config['id'], config['name']),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildInfoChip(
                      'Timeout',
                      '${config['timeout_ms'] ?? 30000}ms',
                      Icons.timer,
                    ),
                    const SizedBox(width: 12),
                    _buildInfoChip(
                      'Max Retries',
                      '${config['max_retries'] ?? 3}',
                      Icons.replay,
                    ),
                    if (config['last_tested_at'] != null) ...[
                      const SizedBox(width: 12),
                      _buildInfoChip(
                        'Last Test',
                        _formatDate(config['last_tested_at']),
                        Icons.history,
                      ),
                    ],
                    if (config['last_test_status'] != null) ...[
                      const SizedBox(width: 12),
                      _buildStatusChip(config['last_test_status']),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;
    Color textColor;

    switch (status) {
      case 'success':
        color = Colors.green;
        textColor = Colors.green.shade700;
        label = 'Success';
        break;
      case 'failed':
        color = Colors.orange;
        textColor = Colors.orange.shade700;
        label = 'Failed';
        break;
      case 'error':
        color = Colors.red;
        textColor = Colors.red.shade700;
        label = 'Error';
        break;
      default:
        color = Colors.grey;
        textColor = Colors.grey.shade700;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null) return 'Never';
    try {
      final dt = DateTime.parse(date);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (e) {
      return 'Unknown';
    }
  }

  void _showConfigDialog({Map<String, dynamic>? config}) {
    final nameController = TextEditingController(text: config?['name'] ?? '');
    final urlController = TextEditingController(text: config?['base_url'] ?? '');
    final keyController = TextEditingController(
      text: config != null && config['api_key'] != null
          ? config['api_key']
          : '',
    );
    final timeoutController = TextEditingController(
      text: (config?['timeout_ms'] ?? 30000).toString(),
    );
    final retriesController = TextEditingController(
      text: (config?['max_retries'] ?? 3).toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(config == null ? 'Add Router' : 'Edit Router'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Iyan Router',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://routers.iyantama.tech',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'API Key / Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: timeoutController,
                      decoration: const InputDecoration(
                        labelText: 'Timeout (ms)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: retriesController,
                      decoration: const InputDecoration(
                        labelText: 'Max Retries',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final baseUrl = urlController.text.trim();
              final apiKey = keyController.text.trim();

              if (name.isEmpty || baseUrl.isEmpty || apiKey.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Semua field wajib diisi')),
                );
                return;
              }

              Navigator.pop(dialogContext);

              await _saveConfig(
                existing: config,
                name: name,
                baseUrl: baseUrl,
                apiKey: apiKey,
                timeoutMs: int.tryParse(timeoutController.text) ?? 30000,
                maxRetries: int.tryParse(retriesController.text) ?? 3,
              );
            },
            child: Text(config == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }
}
