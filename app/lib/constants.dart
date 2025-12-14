// Backend URL Configuration
// Build command for production:
// flutter build apk --dart-define=BACKEND_URL=https://aith-backend.onrender.com
// flutter build ios --dart-define=BACKEND_URL=https://aith-backend.onrender.com
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8000', // Development default
);

// For development convenience, you can also use these:
// Android Emulator: http://10.0.2.2:8000
// iOS Simulator: http://127.0.0.1:8000
// Physical Device: http://<YOUR_LOCAL_IP>:8000

// Global Persona (used in ChatScreen)
String globalPersona = 'gentle';

// ========== Navigation Route Constants ==========
// Bottom Navigation Tab Indices
class NavTab {
  static const int dashboard = 0;
  static const int chat = 1;
  static const int library = 2;
  static const int review = 3;
  static const int lecture = 4;
  static const int voiceTutor = 5;
  static const int roadmap = 6;
  static const int analytics = 7;
  static const int examPlanner = 8;
  static const int profile = 9;
}

// Special Route Identifiers (for screens not in bottom nav)
class SpecialRoute {
  static const int parentConnect = -1;
  static const int essayCorrection = -2;
  static const int studyRoom = -3;
  static const int flashcard = -4;
  static const int reviewDirect = -5;
  static const int settings = -6;
  static const int mockInterview = -7;
  static const int classRecorder = -8;
  static const int debate = -9;
  static const int contentGenerator = -10;
}
