// lib/models/focus_session.dart

class FocusSession {
  // 1. Properties
  // The '?' means this can be null (just like Optional[int] in Python)
  final int? id; 
  final String goalDescription;
  final int durationMinutes;
  final String status;

  // 2. The Constructor
  // 'required' enforces that you cannot create this object without these fields.
  FocusSession({
    this.id,
    required this.goalDescription,
    required this.durationMinutes,
    this.status = 'active',
  });

  // 3. The Serialization Method (Dart -> JSON)
  // This translates our Dart object into the exact map that FastAPI expects.
  Map<String, dynamic> toJson() {
    return {
      'goal_description': goalDescription,
      'duration_minutes': durationMinutes,
      // Hardcoding user_id to 1 for now until we build an authentication system
      'user_id': 1, 
    };
  }
}