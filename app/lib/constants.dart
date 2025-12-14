// Backend URL Configuration
const String backendUrl = 'http://172.20.10.7:8000'; // Physical Device (Local IP)
// const String backendUrl = 'http://10.0.2.2:8000'; // Android Emulator
// const String backendUrl = 'http://127.0.0.1:8000'; // iOS Simulator / Web

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
