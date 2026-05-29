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
  /// Defaults to 127.0.0.1 for local macOS dev.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  /// API Access token resolved at compile time via --dart-define=API_KEY=`token`
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
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
}
