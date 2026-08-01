import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class AdminService {
  final String _token;

  AdminService(this._token);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  // Models Management
  Future<List<dynamic>> getModels() async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/models'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['models'] as List<dynamic>;
    }
    throw Exception('Failed to load models: ${response.body}');
  }

  Future<Map<String, dynamic>> createModel(Map<String, dynamic> model) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/models'),
      headers: _headers,
      body: jsonEncode(model),
    );
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['model'];
    }
    throw Exception('Failed to create model: ${response.body}');
  }

  Future<Map<String, dynamic>> updateModel(
      String id, Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('${AppConstants.backendUrl}/api/admin/models/$id'),
      headers: _headers,
      body: jsonEncode(updates),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['model'];
    }
    throw Exception('Failed to update model: ${response.body}');
  }

  Future<void> deleteModel(String id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.backendUrl}/api/admin/models/$id'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete model: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> toggleModel(String id) async {
    final response = await http.patch(
      Uri.parse('${AppConstants.backendUrl}/api/admin/models/$id/toggle'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['model'];
    }
    throw Exception('Failed to toggle model: ${response.body}');
  }

  // Router Configuration
  Future<List<dynamic>> getRouterConfigs() async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['configs'] as List<dynamic>;
    }
    throw Exception('Failed to load router configs: ${response.body}');
  }

  Future<Map<String, dynamic>> createRouterConfig(
      Map<String, dynamic> config) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router'),
      headers: _headers,
      body: jsonEncode(config),
    );
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['config'];
    }
    throw Exception('Failed to create router config: ${response.body}');
  }

  Future<Map<String, dynamic>> updateRouterConfig(
      int id, Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router/$id'),
      headers: _headers,
      body: jsonEncode(updates),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['config'];
    }
    throw Exception('Failed to update router config: ${response.body}');
  }

  Future<Map<String, dynamic>> testRouterConnection(int id) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router/$id/test'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to test router: ${response.body}');
  }

  Future<Map<String, dynamic>> syncModelsFromRouter() async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router/sync-models'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to sync models: ${response.body}');
  }

  Future<void> deleteRouterConfig(int id) async {
    final response = await http.delete(
      Uri.parse('${AppConstants.backendUrl}/api/admin/router/$id'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete router config: ${response.body}');
    }
  }

  // Promotions
  Future<List<dynamic>> getPromotions() async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/promotions'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['promotions'] as List<dynamic>;
    }
    throw Exception('Failed to load promotions: ${response.body}');
  }

  Future<Map<String, dynamic>> getPromotion(int id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/promotions/$id'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load promotion: ${response.body}');
  }

  Future<Map<String, dynamic>> createPromotion(
      Map<String, dynamic> promo) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/promotions'),
      headers: _headers,
      body: jsonEncode(promo),
    );
    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['promotion'];
    }
    throw Exception('Failed to create promotion: ${response.body}');
  }

  Future<Map<String, dynamic>> updatePromotion(
      int id, Map<String, dynamic> updates) async {
    final response = await http.put(
      Uri.parse('${AppConstants.backendUrl}/api/admin/promotions/$id'),
      headers: _headers,
      body: jsonEncode(updates),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['promotion'];
    }
    throw Exception('Failed to update promotion: ${response.body}');
  }

  Future<void> assignPromotion(int promoId, List<int> userIds) async {
    final response = await http.post(
      Uri.parse('${AppConstants.backendUrl}/api/admin/promotions/$promoId/assign'),
      headers: _headers,
      body: jsonEncode({'user_ids': userIds}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to assign promotion: ${response.body}');
    }
  }

  // Users
  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    int limit = 50,
    String search = '',
    String role = '',
  }) async {
    final queryParams = {
      'page': page.toString(),
      'limit': limit.toString(),
      if (search.isNotEmpty) 'search': search,
      if (role.isNotEmpty) 'role': role,
    };

    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/users')
          .replace(queryParameters: queryParams),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load users: ${response.body}');
  }

  Future<Map<String, dynamic>> getUserDetails(int id) async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/users/$id'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load user: ${response.body}');
  }

  Future<Map<String, dynamic>> getUserStats() async {
    final response = await http.get(
      Uri.parse('${AppConstants.backendUrl}/api/admin/users/stats/summary'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load user stats: ${response.body}');
  }
}
