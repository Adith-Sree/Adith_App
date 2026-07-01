// lib/services/api_service.dart
//
// Base URL Resolution Order (checked at compile time via --dart-define):
//
//   1. PRODUCTION (Render/Railway cloud):
//      flutter build apk --dart-define=API_BASE_URL=https://your-app.onrender.com/api --dart-define=API_KEY=your_secure_token
//
//   2. Local macOS dev:
//      flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
//
//   3. Android emulator (AVD):
//      flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
//
//   4. Physical Pixel 8 Pro (same WiFi as your Mac):
//      flutter run -d <device-id> --dart-define=API_BASE_URL=http://192.168.x.x:8000/api
//
// The fallback default below covers local macOS testing without any --dart-define flag.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/focus_session.dart';
import '../models/analytics_response.dart';

class ApiService {
  /// Resolved at compile time. Set via --dart-define=API_BASE_URL=`url`
  /// Defaults to production DigitalOcean app URL.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://shark-app-dsh7f.ondigitalocean.app/api',
  );

  /// API Access token resolved at compile time via --dart-define=API_KEY=`token`
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: 'DeepWorkLifeOSSecureToken2026',
  );

  /// Dynamically builds the security request headers
  Map<String, String> get _authHeaders {
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  // ─────────────────────────────────────────────────────────────────
  // 1. Fetch Analytics (live score + 7-day graph + session history)
  // ─────────────────────────────────────────────────────────────────
  Future<AnalyticsResponse> fetchAnalytics({int userId = 1}) async {
    final url = Uri.parse('$baseUrl/users/$userId/analytics');
    try {
      final response = await http.get(
        url,
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 8));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return AnalyticsResponse.fromJson(json);
      }
      return AnalyticsResponse.empty();
    } catch (_) {
      return AnalyticsResponse.empty();
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 2. Start a Session
  // ─────────────────────────────────────────────────────────────────
  Future<int?> startSession(FocusSession session) async {
    final url = Uri.parse('$baseUrl/sessions/start');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode(session.toJson()),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['id'] as int?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 3. Abandon — AI Pushback Stream
  // ─────────────────────────────────────────────────────────────────
  Future<void> abandonSessionStream(
    int sessionId,
    Function(String) onChunk,
    Function() onSuccess,
  ) async {
    final url = Uri.parse('$baseUrl/sessions/$sessionId/abandon');
    final request = http.Request('POST', url);
    
    // Wire authorization headers to the HTTP Request instance
    if (apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }
    
    try {
      final response = await http.Client().send(request);
      if (response.statusCode == 409) {
        await for (var chunk in response.stream.transform(utf8.decoder)) {
          onChunk(chunk);
        }
      } else if (response.statusCode == 200) {
        onSuccess();
      }
    } catch (_) {
      onChunk('\n[NETWORK ERROR: Connection Dropped]');
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 4. Force Stop — Hard Terminate with DB-calculated Penalty
  // ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> forceStopSession(int sessionId) async {
    final url = Uri.parse('$baseUrl/sessions/$sessionId/force-stop');
    try {
      final response = await http.post(
        url,
        headers: _authHeaders,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 5. Complete — Timer Expired Naturally (+25 pts)
  // ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> completeSession(int sessionId) async {
    final url = Uri.parse('$baseUrl/sessions/$sessionId/complete');
    try {
      final response = await http.post(
        url,
        headers: _authHeaders,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // 6. Task Checklist Goals Persistence Endpoints
  // ─────────────────────────────────────────────────────────────────
  
  /// Fetches all checklist goals from the DB for a specific user.
  Future<List<Map<String, dynamic>>> fetchGoals({int userId = 1}) async {
    final url = Uri.parse('$baseUrl/goals/users/$userId');
    try {
      final response = await http.get(
        url,
        headers: _authHeaders,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        return decoded.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Adds a new task goal in the database. Deadline is mandatory.
  Future<Map<String, dynamic>?> addGoal(String title, DateTime deadline, {int userId = 1}) async {
    final url = Uri.parse('$baseUrl/goals');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode({
          'title': title,
          'user_id': userId,
          // ISO date format: "2026-07-15"
          'deadline': "${deadline.year.toString().padLeft(4, '0')}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')}",
        }),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Toggles the checkbox done value of a goal in the database.
  Future<bool> toggleGoal(int goalId, bool done) async {
    final url = Uri.parse('$baseUrl/goals/$goalId/toggle');
    try {
      final response = await http.patch(
        url,
        headers: {
          'Content-Type': 'application/json',
          ..._authHeaders,
        },
        body: jsonEncode({
          'done': done,
        }),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Deletes a goal from the database.
  Future<bool> deleteGoal(int goalId) async {
    final url = Uri.parse('$baseUrl/goals/$goalId');
    try {
      final response = await http.delete(
        url,
        headers: _authHeaders,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
