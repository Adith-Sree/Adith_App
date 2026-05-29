// lib/models/analytics_response.dart
//
// Dart mirror of the JSON returned by GET /api/users/{user_id}/analytics
// {
//   "discipline_score": 75,
//   "graph_points":     [0, 0, 25, 25, 0, 50, 75],
//   "session_history":  [ { id, goal_description, duration_minutes,
//                           status, score_delta, start_time, end_time }, ... ]
// }

class SessionRecord {
  final int id;
  final String goalDescription;
  final int durationMinutes;
  final String status; // "active" | "completed" | "failed"
  final int scoreDelta;
  final DateTime? startTime;
  final DateTime? endTime;

  const SessionRecord({
    required this.id,
    required this.goalDescription,
    required this.durationMinutes,
    required this.status,
    required this.scoreDelta,
    this.startTime,
    this.endTime,
  });

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      id: json['id'] as int,
      goalDescription: json['goal_description'] as String,
      durationMinutes: json['duration_minutes'] as int,
      status: json['status'] as String,
      scoreDelta: json['score_delta'] as int,
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'] as String)
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'] as String)
          : null,
    );
  }

  /// Human-readable date string for the Sessions tab list
  String get dateLabel {
    if (endTime == null) return 'Ongoing';
    final d = endTime!.toLocal();
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  /// Signed score string e.g. "+25 pts" or "-15 pts"
  String get scoreDeltaLabel =>
      scoreDelta >= 0 ? '+$scoreDelta pts' : '$scoreDelta pts';

  bool get isCompleted => status == 'completed';
}

class AnalyticsResponse {
  /// Live discipline score from the User table
  final int disciplineScore;

  /// 7 cumulative data points for the line graph (index 0 = 6 days ago)
  final List<double> graphPoints;

  /// Last 20 finished sessions, most recent first
  final List<SessionRecord> sessionHistory;

  const AnalyticsResponse({
    required this.disciplineScore,
    required this.graphPoints,
    required this.sessionHistory,
  });

  factory AnalyticsResponse.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['graph_points'] as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    final history = (json['session_history'] as List<dynamic>)
        .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    return AnalyticsResponse(
      disciplineScore: json['discipline_score'] as int,
      graphPoints: rawPoints,
      sessionHistory: history,
    );
  }

  /// Returns an empty response — used while loading or when DB is empty
  factory AnalyticsResponse.empty() {
    return const AnalyticsResponse(
      disciplineScore: 0,
      graphPoints: [0, 0, 0, 0, 0, 0, 0],
      sessionHistory: [],
    );
  }
}
