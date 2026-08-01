import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/admin_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  String? _error;

  final ApiService _api = ApiService();
  late final AdminService _adminService;

  final List<_AdminSection> _sections = [
    _AdminSection(
      title: 'Dashboard',
      icon: Icons.dashboard,
      route: '/admin',
    ),
    _AdminSection(
      title: 'Models',
      icon: Icons.memory,
      route: '/admin/models',
    ),
    _AdminSection(
      title: 'Router',
      icon: Icons.router,
      route: '/admin/router',
    ),
    _AdminSection(
      title: 'Promotions',
      icon: Icons.local_offer,
      route: '/admin/promotions',
    ),
    _AdminSection(
      title: 'Users',
      icon: Icons.people,
      route: '/admin/users',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(_api.token ?? '');
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _adminService.getUserStats();
      setState(() {
        _stats = data['stats'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
              Navigator.pushNamed(context, _sections[index].route);
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            destinations: _sections.map((section) {
              return NavigationRailDestination(
                icon: Icon(section.icon),
                label: Text(section.title),
              );
            }).toList(),
            leading: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Admin',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Only show Dashboard home here, other sections navigate to dedicated screens
    return _buildDashboardHome();
  }

  Widget _buildDashboardHome() {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load stats', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final stats = _stats ?? {};
    final totalUsers = stats['total_users']?.toString() ?? '0';
    final active24h = stats['active_24h']?.toString() ?? '0';
    final active7d = stats['active_7d']?.toString() ?? '0';
    final newUsers7d = stats['new_7d']?.toString() ?? '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dashboard Overview',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh stats',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Stats cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2,
            children: [
              _buildStatCard(
                'Total Users',
                totalUsers,
                Icons.people,
                theme.colorScheme.primary,
              ),
              _buildStatCard(
                'Active (24h)',
                active24h,
                Icons.access_time,
                theme.colorScheme.secondary,
              ),
              _buildStatCard(
                'Active (7d)',
                active7d,
                Icons.calendar_today,
                theme.colorScheme.tertiary,
              ),
              _buildStatCard(
                'New Users (7d)',
                newUsers7d,
                Icons.person_add,
                Colors.green,
              ),
            ],
          ),

          const SizedBox(height: 32),

          Text(
            'Quick Actions',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildActionButton(
                'Manage Models',
                Icons.memory,
                () => Navigator.pushNamed(context, '/admin/models'),
              ),
              _buildActionButton(
                'Manage Users',
                Icons.people,
                () => Navigator.pushNamed(context, '/admin/users'),
              ),
              _buildActionButton(
                'Router Config',
                Icons.router,
                () => Navigator.pushNamed(context, '/admin/router'),
              ),
              _buildActionButton(
                'Promotions',
                Icons.local_offer,
                () => Navigator.pushNamed(context, '/admin/promotions'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

class _AdminSection {
  final String title;
  final IconData icon;
  final String route;

  _AdminSection({
    required this.title,
    required this.icon,
    required this.route,
  });
}
