import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Local imports - newly extracted modules
import 'constants.dart';
import 'models/message.dart';
import 'utils/latex_syntax.dart';
import 'utils/latex_builder.dart';
import 'widgets/challenge_dialog.dart';

// Note: backendUrl is now imported from constants.dart

// Import extracted screen groups
import 'screens/learning_screens.dart';
import 'screens/practice_screens.dart';
import 'screens/communication_screens.dart';
import 'screens/placeholder_screens.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';


void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();
    runApp(const AithApp());
  } catch (e, stack) {
    runApp(ErrorApp(error: e.toString(), stack: stack.toString()));
  }
}

class ErrorApp extends StatelessWidget {
  final String error;
  final String stack;
  const ErrorApp({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                const Text(
                  'Initialization Error',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 16),
                Text(error, style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 16),
                const Text('Stack Trace:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(stack, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AithApp extends StatelessWidget {
  const AithApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AITH',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF), // Modern Violet
          brightness: Brightness.light,
          surface: const Color(0xFFF8F9FE), // Light Blue-Grey background
        ),
        textTheme: GoogleFonts.notoSansJpTextTheme(
          Theme.of(context).textTheme,
        ),
        // cardTheme: CardTheme(
        //   elevation: 0,
        //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        //   color: Colors.white,
        //   margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        // ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.bold),
          iconTheme: IconThemeData(color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

/// Wrapper widget that handles authentication state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A2E),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ),
          );
        }

        // User is logged in
        if (snapshot.hasData) {
          return const HomeScreen();
        }

        // User is not logged in
        return LoginScreen(
          onLoginSuccess: () {
            // Force rebuild by navigating
          },
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const DashboardScreen(), // New Home
    const ChatScreen(),
    const LibraryScreen(),
    const ReviewScreen(),
    const LectureScreen(),
    const VoiceTutorScreen(),
    const RoadmapScreen(),
    const AnalyticsScreen(),
    const ExamPlannerScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildNavItem(0, Icons.dashboard_rounded, "ホーム"),
                  _buildNavItem(1, Icons.chat_bubble_rounded, "AIチャット"),
                  _buildNavItem(2, Icons.library_books_rounded, "学習"),
                  _buildNavItem(3, Icons.refresh_rounded, "復習"),
                  _buildNavItem(4, Icons.school_rounded, "授業"),
                  _buildNavItem(5, Icons.mic_rounded, "英会話"),
                  _buildNavItem(6, Icons.map_rounded, "進路"),
                  _buildNavItem(7, Icons.bar_chart_rounded, "分析"),
                  _buildNavItem(8, Icons.calendar_month_rounded, "計画"),
                  _buildNavItem(9, Icons.person_rounded, "設定"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _userStats;

  @override
  void initState() {
    super.initState();
    _fetchUserStats();
  }

  Future<void> _fetchUserStats() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/user_stats/demo_user'));
      if (response.statusCode == 200) {
        setState(() {
          _userStats = jsonDecode(response.body);
        });
      }
    } catch (e) {
      print("Error fetching stats: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final level = _userStats?['level'] ?? 1;
    final progress = _userStats?['progress'] ?? 0.0;
    final nextLevelXp = _userStats?['next_level_xp'] ?? 100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Hello, User! 👋", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Text("Lv.$level  あと${nextLevelXp}XPでレベルアップ", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                    ],
                  ),
                  const CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage("https://i.pravatar.cc/150?img=12"), // Placeholder
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Daily Progress (Bento Large)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF8B85FF)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Row(
                  children: [
                    CircularPercentIndicator(
                      radius: 40.0,
                      lineWidth: 8.0,
                      percent: progress.toDouble(),
                      center: Text("${(progress * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      progressColor: Colors.white,
                      backgroundColor: Colors.white24,
                      circularStrokeCap: CircularStrokeCap.round,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("現在のレベル: $level", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          const Text("レベルアップ目指して頑張ろう！", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          // Text("学習時間: 45分 / 60分", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.2, end: 0),

              const SizedBox(height: 24),
              const Text("クイックアクション", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Grid Actions
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildActionCard(context, "AIチャット", Icons.chat_bubble_outline, Colors.orange, NavTab.chat),
                  _buildActionCard(context, "カメラ解説", Icons.camera_alt_outlined, Colors.blue, NavTab.chat),
                  _buildActionCard(context, "今日の復習", Icons.refresh, Colors.green, NavTab.review),
                  _buildActionCard(context, "英会話", Icons.mic_none, Colors.pink, NavTab.voiceTutor),
                  _buildActionCard(context, "保護者レポート", Icons.family_restroom, Colors.purple, SpecialRoute.parentConnect),
                  _buildActionCard(context, "記述添削", Icons.edit_note, Colors.teal, SpecialRoute.essayCorrection),
                  _buildActionCard(context, "自習室", Icons.meeting_room, Colors.indigo, SpecialRoute.studyRoom),
                  _buildActionCard(context, "単語帳", Icons.style, Colors.orange, SpecialRoute.flashcard),
                  _buildActionCard(context, "究極の復習", Icons.repeat, Colors.redAccent, SpecialRoute.reviewDirect),
                  _buildActionCard(context, "AI面接", Icons.record_voice_over, Colors.blueGrey, SpecialRoute.mockInterview),
                  _buildActionCard(context, "授業要約", Icons.summarize, Colors.brown, SpecialRoute.classRecorder),
                  _buildActionCard(context, "AIディベート", Icons.gavel, Colors.deepPurple, SpecialRoute.debate),
                  _buildActionCard(context, "AI教材生成", Icons.auto_stories, Colors.cyan, SpecialRoute.contentGenerator),
                  _buildActionCard(context, "設定", Icons.settings, Colors.grey, SpecialRoute.settings),
                ],
              ),

              const SizedBox(height: 24),
              const Text("学習の記録", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              // Recent Activity
              Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.history, color: Colors.blue),
                  ),
                  title: const Text("数学: 二次関数"),
                  subtitle: const Text("昨日 • スコア 80%"),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ).animate().fadeIn().slideX(begin: 0.2, end: 0, delay: 200.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, int tabIndex) {
    return GestureDetector(
      onTap: () {
        if (tabIndex == SpecialRoute.parentConnect) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ParentConnectScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.essayCorrection) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const EssayCorrectionScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.studyRoom) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const StudyRoomScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.flashcard) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const FlashcardScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.reviewDirect) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ReviewScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.settings) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.mockInterview) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const MockInterviewScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.classRecorder) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ClassRecorderScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.debate) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const DebateScreen()));
          return;
        }
        if (tabIndex == SpecialRoute.contentGenerator) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const ContentGeneratorScreen()));
          return;
        }

        // Find HomeScreenState and switch tab
        final state = context.findAncestorStateOfType<_HomeScreenState>();
        if (state != null) {
          state.setState(() {
            state._currentIndex = tabIndex;
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    ).animate().scale(delay: 100.ms);
  }
}

class ContentGeneratorScreen extends StatefulWidget {
  const ContentGeneratorScreen({super.key});

  @override
  State<ContentGeneratorScreen> createState() => _ContentGeneratorScreenState();
}

class _ContentGeneratorScreenState extends State<ContentGeneratorScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController(text: "高校1年生");
  bool _isLoading = false;
  String? _generatedTextbook;
  List<dynamic>? _generatedDrills;
  List<dynamic> _sharedContent = [];

  // Standard Curriculum Data
  final Map<String, List<String>> _curriculum = {
    "数学": ["数と式", "二次関数", "三角比", "場合の数", "確率", "整数の性質"],
    "英語": ["時制", "助動詞", "仮定法", "不定詞", "動名詞", "分詞", "関係詞"],
    "歴史": ["古代文明", "鎌倉幕府", "戦国時代", "江戸幕府", "明治維新", "世界大戦"],
    "理科": ["力と運動", "エネルギー", "化学反応", "生物の恒常性", "宇宙の構成"],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Increased to 4
    _fetchSharedContent();
  }

  Future<void> _fetchSharedContent() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/shared_content'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _sharedContent = data['contents'];
        });
      }
    } catch (e) {
      print("Fetch Shared Content Error: $e");
    }
  }

  Future<void> _shareContent(String type) async {
    if ((type == 'textbook' && _generatedTextbook == null) || (type == 'drill' && _generatedDrills == null)) return;

    final content = type == 'textbook' ? _generatedTextbook! : jsonEncode(_generatedDrills);
    final title = "${_topicController.text} (${_gradeController.text})";

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/share_content'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'type': type,
          'content': content,
          'author': 'User' // In real app, use user name
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('共有しました！')));
        _fetchSharedContent(); // Refresh list
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  Future<void> _generateContent(String topic, String grade, {bool isDrill = false}) async {
    setState(() {
      _isLoading = true;
      _generatedTextbook = null;
      _generatedDrills = null;
      _topicController.text = topic;
      _tabController.animateTo(isDrill ? 2 : 1);
    });

    try {
      final endpoint = !isDrill ? 'generate_textbook' : 'generate_drill';
      
      final response = await http.post(
        Uri.parse('$backendUrl/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'topic': topic,
          'grade': grade
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          if (!isDrill) {
            _generatedTextbook = data['content'];
          } else {
            _generatedDrills = data['drills'];
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadSharedContent(Map<String, dynamic> item) {
    setState(() {
      _topicController.text = item['title'];
      if (item['type'] == 'textbook') {
        _generatedTextbook = item['content'];
        _tabController.animateTo(1);
      } else {
        _generatedDrills = jsonDecode(item['content']);
        _tabController.animateTo(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI教材生成"),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "ライブラリ"),
            Tab(text: "教科書"),
            Tab(text: "ドリル"),
            Tab(text: "みんなの教材"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Library Tab
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text("学習したいテーマを選んでください", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ..._curriculum.entries.map((entry) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyan)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.value.map((topic) => ActionChip(
                      label: Text(topic),
                      onPressed: () => _showGenerationDialog(topic),
                    )).toList(),
                  ),
                  const Divider(height: 32),
                ],
              )),
              const SizedBox(height: 24),
              const Text("カスタム生成", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(
                  labelText: '自由入力（例: 量子力学、フランス革命）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _gradeController,
                decoration: const InputDecoration(
                  labelText: '対象学年',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _generateContent(_topicController.text, _gradeController.text),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("カスタムテーマで生成", style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),

          // Textbook Tab
          _isLoading && _tabController.index == 1
              ? const Center(child: CircularProgressIndicator())
              : (_generatedTextbook != null
                  ? Scaffold(
                      floatingActionButton: FloatingActionButton(
                        heroTag: 'textbook_share_fab',
                        onPressed: () => _shareContent('textbook'),
                        child: const Icon(Icons.share),
                      ),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: MarkdownBody(data: _generatedTextbook!),
                      ),
                    )
                  : const Center(child: Text("ライブラリからテーマを選択してください"))),
          
          // Drill Tab
          _isLoading && _tabController.index == 2
              ? const Center(child: CircularProgressIndicator())
              : (_generatedDrills != null
                  ? Scaffold(
                      floatingActionButton: FloatingActionButton(
                        heroTag: 'drill_share_fab',
                        onPressed: () => _shareContent('drill'),
                        child: const Icon(Icons.share),
                      ),
                      body: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _generatedDrills!.length,
                        itemBuilder: (context, index) {
                          final drill = _generatedDrills![index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Q${index + 1}. ${drill['question']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  ...List<String>.from(drill['options']).map((opt) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text("・ $opt"),
                                  )),
                                  const Divider(),
                                  ExpansionTile(
                                    title: const Text("答えを見る"),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text("正解: ${drill['answer']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                                            const SizedBox(height: 4),
                                            Text("解説: ${drill['explanation']}"),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : const Center(child: Text("ライブラリからテーマを選択してください"))),

          // Community Tab
          RefreshIndicator(
            onRefresh: _fetchSharedContent,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _sharedContent.length,
              itemBuilder: (context, index) {
                final item = _sharedContent[index];
                return Card(
                  child: ListTile(
                    leading: Icon(
                      item['type'] == 'textbook' ? Icons.menu_book : Icons.quiz,
                      color: item['type'] == 'textbook' ? Colors.blue : Colors.orange,
                    ),
                    title: Text(item['title']),
                    subtitle: Text("作成者: ${item['author']}"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _loadSharedContent(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showGenerationDialog(String topic) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(topic),
        content: const Text("どちらを生成しますか？"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _generateContent(topic, _gradeController.text, isDrill: false);
            },
            child: const Text("教科書"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _generateContent(topic, _gradeController.text, isDrill: true);
            },
            child: const Text("ドリル"),
          ),
        ],
      ),
    );
  }
}

class DebateScreen extends StatefulWidget {
  const DebateScreen({super.key});

  @override
  State<DebateScreen> createState() => _DebateScreenState();
}

class _DebateScreenState extends State<DebateScreen> {
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _argumentController = TextEditingController();
  List<Map<String, dynamic>> _history = [];
  bool _isStarted = false;
  bool _isLoading = false;

  Future<void> _sendArgument() async {
    if (_argumentController.text.isEmpty) return;
    
    final userArg = _argumentController.text;
    setState(() {
      _history.add({"role": "user", "text": userArg});
      _argumentController.clear();
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/debate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'topic': _topicController.text,
          'user_argument': userArg,
          'history': _history
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _history.add({
            "role": "ai",
            "text": data['rebuttal'],
            "score": data['logic_score'],
            "advice": data['advice']
          });
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AIディベート")),
      body: Column(
        children: [
          if (!_isStarted) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.gavel, size: 80, color: Colors.deepPurple),
                  const SizedBox(height: 24),
                  const Text("議論したいテーマを入力してください", style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _topicController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'テーマ（例: 学校にスマホは必要か？）',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      if (_topicController.text.isNotEmpty) {
                        setState(() => _isStarted = true);
                      }
                    },
                    child: const Text("議論を開始する"),
                  ),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final msg = _history[index];
                  final isAi = msg['role'] == 'ai';
                  return Column(
                    crossAxisAlignment: isAi ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAi ? Colors.grey[200] : Colors.deepPurple[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(msg['text']),
                            if (isAi) ...[
                              const SizedBox(height: 8),
                              Text("論理性スコア: ${msg['score']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                              Text("アドバイス: ${msg['advice']}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _argumentController,
                      decoration: const InputDecoration(
                        hintText: 'あなたの意見を入力...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isLoading ? const CircularProgressIndicator() : const Icon(Icons.send),
                    onPressed: _isLoading ? null : _sendArgument,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ClassRecorderScreen extends StatefulWidget {
  const ClassRecorderScreen({super.key});

  @override
  State<ClassRecorderScreen> createState() => _ClassRecorderScreenState();
}

class _ClassRecorderScreenState extends State<ClassRecorderScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessing = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        _processAudio(path);
      }
    } else {
      if (await Permission.microphone.request().isGranted) {
        final directory = await Directory.systemTemp.createTemp();
        final path = '${directory.path}/class_audio.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() => _isProcessing = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/summarize_class'));
      request.files.add(await http.MultipartFile.fromPath('file', path));

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _result = jsonDecode(respStr);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("授業レコーダー")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_result == null) ...[
              const Spacer(),
              GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red : Colors.brown,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15)],
                  ),
                  child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 64),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _isProcessing ? "AIが授業を分析中..." : (_isRecording ? "録音中..." : "タップして録音開始"),
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const Spacer(),
            ] else ...[
              Expanded(
                child: ListView(
                  children: [
                    const Text("要約", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_result!['summary']),
                    const Divider(height: 32),
                    const Text("重要キーワード", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8,
                      children: List<String>.from(_result!['keywords']).map((k) => Chip(label: Text(k))).toList(),
                    ),
                    const Divider(height: 32),
                    const Text("復習クイズ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ...List<dynamic>.from(_result!['quiz']).map((q) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ExpansionTile(
                        title: Text(q['question']),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text("答え: ${q['answer']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => setState(() => _result = null),
                child: const Text("新しい授業を録音する"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MockExamSetupScreen extends StatefulWidget {
  const MockExamSetupScreen({super.key});

  @override
  State<MockExamSetupScreen> createState() => _MockExamSetupScreenState();
}

class _MockExamSetupScreenState extends State<MockExamSetupScreen> {
  String _selectedSubject = '数学';
  final List<String> _subjects = ['数学', '英語', '理科', '社会', '国語', '総合'];
  bool _isLoading = false;

  Future<void> _startExam() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/generate_mock_exam'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'subject': _selectedSubject,
          'grade': '中学2年生', // TODO: Get from profile
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final exam = data['exam'];
        if (exam != null && exam['questions'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MockExamScreen(
                questions: exam['questions'],
                subject: _selectedSubject,
              ),
            ),
          );
        }
      } else {
        throw Exception('Failed to generate exam');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模試に挑戦')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("教科を選択してください", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              children: _subjects.map((subject) {
                return ChoiceChip(
                  label: Text(subject),
                  selected: _selectedSubject == subject,
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedSubject = subject);
                  },
                );
              }).toList(),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _startExam,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("試験開始", style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MockExamScreen extends StatefulWidget {
  final List<dynamic> questions;
  final String subject;

  const MockExamScreen({super.key, required this.questions, required this.subject});

  @override
  State<MockExamScreen> createState() => _MockExamScreenState();
}

class _MockExamScreenState extends State<MockExamScreen> {
  int _currentIndex = 0;
  final Map<int, int> _answers = {}; // index -> selectedOption
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    super.dispose();
  }

  Future<void> _finishExam() async {
    _stopwatch.stop();
    final durationSeconds = _stopwatch.elapsed.inSeconds;
    
    // Calculate score & Identify mistakes
    int score = 0;
    List<Map<String, dynamic>> mistakes = [];
    
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final userAnswer = _answers[i];
      
      if (userAnswer == q['answer_index']) {
        score++;
      } else {
        mistakes.add({
          'question': q['question'],
          'options': q['options'],
          'answer_index': q['answer_index'],
          'explanation': q['explanation'],
          'subject': widget.subject,
        });
      }
    }

    // Send log
    try {
      await http.post(
        Uri.parse('$backendUrl/record_study_log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'type': 'mock_exam',
          'subject': widget.subject,
          'duration_seconds': durationSeconds,
          'score': score,
          'total_questions': widget.questions.length,
        }),
      );

      // Register Mistakes
      if (mistakes.isNotEmpty) {
        await http.post(
          Uri.parse('$backendUrl/register_mistakes'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_id': 'demo_user',
            'questions': mistakes,
          }),
        );
      }
    } catch (e) {
      print("Error recording log/mistakes: $e");
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MockExamResultScreen(
          questions: widget.questions,
          answers: _answers,
          score: score,
          durationSeconds: durationSeconds,
        ),
      ),
    );
  }

  Widget _buildMarkdown(String text) {
     // Helper duplicate
     return MarkdownBody(
        data: text.replaceAllMapped(
          RegExp(r'(?<!\$|\\)(\\[a-zA-Z]+(?:\s*\{(?:[^{}]|\{[^{}]*\})*\})*)'), 
          (match) => '\$${match.group(1)}\$',
        ).replaceAllMapped(
          RegExp(r'(?<!\$)\b([a-zA-Z0-9]+\^[a-zA-Z0-9]+)\b'),
          (match) => '\$${match.group(1)}\$',
        ),
        selectable: false,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(color: Colors.black87, fontSize: 18),
        ),
        inlineSyntaxes: [LatexSyntax()],
        builders: {
          'latex': LatexElementBuilder(),
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    final questionData = widget.questions[_currentIndex];
    final options = List<String>.from(questionData['options']);

    return Scaffold(
      appBar: AppBar(title: Text("模試: 問${_currentIndex + 1} / ${widget.questions.length}")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMarkdown(questionData['question']),
            const SizedBox(height: 24),
            ...List.generate(options.length, (index) {
              return Card(
                color: _answers[_currentIndex] == index ? Colors.blue[100] : null,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: _buildMarkdown(options[index]),
                  leading: Radio<int>(
                    value: index,
                    groupValue: _answers[_currentIndex],
                    onChanged: (value) {
                      setState(() => _answers[_currentIndex] = value!);
                    },
                  ),
                  onTap: () {
                    setState(() => _answers[_currentIndex] = index);
                  },
                ),
              );
            }),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentIndex > 0)
                  ElevatedButton(
                    onPressed: () => setState(() => _currentIndex--),
                    child: const Text("前へ"),
                  )
                else
                  const SizedBox(),
                
                if (_currentIndex < widget.questions.length - 1)
                  ElevatedButton(
                    onPressed: () => setState(() => _currentIndex++),
                    child: const Text("次へ"),
                  )
                else
                  ElevatedButton(
                    onPressed: _finishExam,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                    child: const Text("試験終了"),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MockExamResultScreen extends StatelessWidget {
  final List<dynamic> questions;
  final Map<int, int> answers;
  final int score;
  final int durationSeconds;

  const MockExamResultScreen({
    super.key,
    required this.questions,
    required this.answers,
    required this.score,
    required this.durationSeconds,
  });

  Widget _buildMarkdown(String text) {
     // Helper duplicate
     return MarkdownBody(
        data: text.replaceAllMapped(
          RegExp(r'(?<!\$|\\)(\\[a-zA-Z]+(?:\s*\{(?:[^{}]|\{[^{}]*\})*\})*)'), 
          (match) => '\$${match.group(1)}\$',
        ).replaceAllMapped(
          RegExp(r'(?<!\$)\b([a-zA-Z0-9]+\^[a-zA-Z0-9]+)\b'),
          (match) => '\$${match.group(1)}\$',
        ),
        selectable: false,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
        inlineSyntaxes: [LatexSyntax()],
        builders: {
          'latex': LatexElementBuilder(),
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("試験結果")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: Colors.white,
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Text("あなたの成績", style: TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text("$score / ${questions.length}", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 8),
                    Text("所要時間: ${(durationSeconds / 60).toStringAsFixed(1)}分", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Align(alignment: Alignment.centerLeft, child: Text("解説", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            const SizedBox(height: 16),
            ...List.generate(questions.length, (index) {
              final q = questions[index];
              final isCorrect = answers[index] == q['answer_index'];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: isCorrect ? Colors.green[50] : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red),
                          const SizedBox(width: 8),
                          Text("問${index + 1}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildMarkdown(q['question']),
                      const Divider(),
                      const Text("解説:", style: TextStyle(fontWeight: FontWeight.bold)),
                      _buildMarkdown(q['explanation']),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("ライブラリに戻る"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<dynamic> _materials = [];
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchMaterials();
  }

  Future<void> _fetchMaterials() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$backendUrl/materials?user_id=demo_user'));
      if (response.statusCode == 200) {
        setState(() {
          _materials = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      print('Error fetching materials: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generatePdf(String title, String content) async {
    final pdf = pw.Document();

    // Load a font that supports Japanese
    final font = await PdfGoogleFonts.notoSansJPRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title, style: pw.TextStyle(font: font, fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text(content, style: pw.TextStyle(font: font, fontSize: 12)),
              pw.Spacer(),
              pw.Text("AITH Virtual Cram School", style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _uploadMaterial() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result == null || result.files.single.path == null) return;
      
      String filePath = result.files.single.path!;

      setState(() => _isLoading = true);

      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/upload_material'));
      request.fields['user_id'] = 'demo_user';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var response = await request.send();

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('資料をアップロードしました')));
        _fetchMaterials(); // Refresh list
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startDrill(String materialId, String subject) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/generate_drill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'material_id': materialId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final drill = data['drill'];
        if (drill != null && drill['questions'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DrillScreen(
                questions: drill['questions'],
                subject: subject,
              ),
            ),
          );
        }
      } else {
        throw Exception('Failed to generate drill');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('マイライブラリ'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'AI教材'),
              Tab(text: '公式テキスト'),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MockExamSetupScreen()),
                );
              },
              icon: const Icon(Icons.assignment_turned_in, color: Colors.redAccent),
              label: const Text("模試に挑戦", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // Tab 1: AI Materials
                  _materials.isEmpty
                      ? const Center(child: Text('資料がありません。\n+ボタンから追加してください。', textAlign: TextAlign.center))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _materials.length,
                          itemBuilder: (context, index) {
                            final material = _materials[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                leading: const Icon(Icons.description, size: 40, color: Colors.blue),
                                title: Text(material['title'] ?? '無題', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(material['summary'] ?? '...'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.print, color: Colors.grey),
                                      onPressed: () => _generatePdf(material['title'] ?? '無題', material['summary'] ?? ''),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red), // New PDF icon
                                      onPressed: () => _generatePdf(material['title'] ?? '無題', material['summary'] ?? ''),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.green, size: 32),
                                      onPressed: () => _startDrill(material['id'], material['subject'] ?? 'その他'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  
                  // Tab 2: Official Texts (Mock)
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("小学生", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("算数", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.calculate, color: Colors.blue),
                        children: [
                          _buildOfficialTextCard("小学算数 1年", "かずとけいさん", "elem_math_1"),
                          _buildOfficialTextCard("小学算数 2年", "たし算・九九", "elem_math_2"),
                          _buildOfficialTextCard("小学算数 3年", "かけ算・わり算", "elem_math_3"),
                          _buildOfficialTextCard("小学算数 4年", "大きな数・小数", "elem_math_4"),
                          _buildOfficialTextCard("小学算数 5年", "分数と小数", "elem_math_5"),
                          _buildOfficialTextCard("小学算数 6年", "分数のかけ算・わり算", "elem_math_6"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("国語", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.menu_book, color: Colors.purple),
                        children: [
                          _buildOfficialTextCard("小学国語 1年", "ひらがな・カタカナ", "elem_japanese_1"),
                          _buildOfficialTextCard("小学国語 2年", "かん字", "elem_japanese_2"),
                          _buildOfficialTextCard("小学国語 3年", "漢字と文章", "elem_japanese_3"),
                          _buildOfficialTextCard("小学国語 4年", "説明文と物語文", "elem_japanese_4"),
                          _buildOfficialTextCard("小学国語 5年", "文章の構成", "elem_japanese_5"),
                          _buildOfficialTextCard("小学国語 6年", "論説文と古典", "elem_japanese_6"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("理科", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.science, color: Colors.green),
                        children: [
                          _buildOfficialTextCard("小学理科 3年", "しぜんのかんさつ", "elem_science_3"),
                          _buildOfficialTextCard("小学理科 4年", "季節と生物", "elem_science_4"),
                          _buildOfficialTextCard("小学理科 5年", "植物の発芽", "elem_science_5"),
                          _buildOfficialTextCard("小学理科 6年", "燃焼と水溶液", "elem_science_6"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("社会", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.public, color: Colors.orange),
                        children: [
                          _buildOfficialTextCard("小学社会 3年", "わたしたちのまち", "elem_social_3"),
                          _buildOfficialTextCard("小学社会 4年", "都道府県", "elem_social_4"),
                          _buildOfficialTextCard("小学社会 5年", "日本の国土", "elem_social_5"),
                          _buildOfficialTextCard("小学社会 6年", "日本の歴史", "elem_social_6"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("中学生", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("数学", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.calculate, color: Colors.blue),
                        initiallyExpanded: false,
                        children: [
                          _buildOfficialTextCard("中学数学 Vol.1", "数と式・方程式", "math_v1"),
                          _buildOfficialTextCard("中学数学 Vol.2", "平面図形・空間図形", "math_v2"),
                          _buildOfficialTextCard("中学数学 Vol.3", "方程式・関数", "math_v3"),
                          _buildOfficialTextCard("中学数学 Vol.4", "確率・データ", "math_v4"),
                          _buildOfficialTextCard("中学数学 Vol.5", "平方根・二次方程式", "math_v5"),
                          _buildOfficialTextCard("中学数学 Vol.6", "二次関数・相似・三平方", "math_v6"),
                          _buildOfficialTextCard("中学数学 Vol.7", "連立方程式", "math_v7"),
                          _buildOfficialTextCard("中学数学 Vol.8", "一次関数", "math_v8"),
                          _buildOfficialTextCard("中学数学 Vol.9", "図形の証明", "math_v9"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("英語", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.language, color: Colors.red),
                        children: [
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.1", "be動詞・一般動詞", "eng_grammar"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.2", "代名詞・形容詞・副詞", "eng_grammar_v2"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.3", "不定詞・動名詞・比較", "eng_grammar_v3"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.4", "受動態・現在完了", "eng_grammar_v4"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.5", "分詞・関係代名詞", "eng_grammar_v5"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.6", "助動詞", "eng_grammar_v6"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.7", "疑問詞", "eng_grammar_v7"),
                          _buildOfficialTextCard("中学英語 文法まとめ Vol.8", "接続詞", "eng_grammar_v8"),
                          _buildOfficialTextCard("英単語ターゲット1000", "基礎〜標準レベル", "eng_vocab"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("理科", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.science, color: Colors.green),
                        children: [
                          _buildOfficialTextCard("中学理科 生物 Vol.1", "植物の生活と種類", "science_bio"),
                          _buildOfficialTextCard("中学理科 生物 Vol.2", "細胞・遺伝", "science_bio_v2"),
                          _buildOfficialTextCard("中学理科 物理 Vol.1", "光・音・力", "science_physics"),
                          _buildOfficialTextCard("中学理科 物理 Vol.2", "電流・磁界", "science_physics_v2"),
                          _buildOfficialTextCard("中学理科 化学 Vol.1", "物質の性質・化学変化", "science_chem"),
                          _buildOfficialTextCard("中学理科 化学 Vol.2", "化学反応式・イオン", "science_chem_v2"),
                          _buildOfficialTextCard("中学理科 地学 Vol.1", "大地の変化・天気", "science_earth"),
                          _buildOfficialTextCard("中学理科 地学 Vol.2", "天体・宇宙", "science_earth_v2"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("社会", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.public, color: Colors.orange),
                        children: [
                          _buildOfficialTextCard("中学社会 歴史年表 Vol.1", "古代〜中世", "social_history"),
                          _buildOfficialTextCard("中学社会 歴史年表 Vol.2", "近世〜近代", "social_history_v2"),
                          _buildOfficialTextCard("中学社会 歴史年表 Vol.3", "現代", "social_history_v3"),
                          _buildOfficialTextCard("中学社会 世界地理 Vol.1", "世界の姿・気候", "social_geo"),
                          _buildOfficialTextCard("中学社会 世界地理 Vol.2", "世界の諸地域", "social_geo_v3"),
                          _buildOfficialTextCard("中学社会 日本地理", "日本の姿・地形", "social_geo_v2"),
                          _buildOfficialTextCard("中学社会 公民 Vol.1", "日本国憲法・政治", "social_civics"),
                          _buildOfficialTextCard("中学社会 公民 Vol.2", "経済・国際社会", "social_civics_v2"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("国語", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.menu_book, color: Colors.purple),
                        children: [
                          _buildOfficialTextCard("中学国語 現代文 Vol.1", "説明文の読解", "japanese_modern_v1"),
                          _buildOfficialTextCard("中学国語 現代文 Vol.2", "小説・物語文", "japanese_modern_v2"),
                          _buildOfficialTextCard("中学国語 古文 Vol.1", "古文の基礎", "japanese_classical_v1"),
                          _buildOfficialTextCard("中学国語 古文 Vol.2", "古典文法", "japanese_classical_v2"),
                          _buildOfficialTextCard("中学国語 漢文 Vol.1", "漢文の基礎", "japanese_kanbun_v1"),
                          _buildOfficialTextCard("中学国語 漢文 Vol.2", "漢文の句法", "japanese_kanbun_v2"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("高校生", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("数学", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.calculate, color: Colors.blue),
                        children: [
                          _buildOfficialTextCard("高校数学 I", "数と式・三角比", "hs_math_1"),
                          _buildOfficialTextCard("高校数学 A", "場合の数と確率", "hs_math_a"),
                          _buildOfficialTextCard("高校数学 II", "三角関数・微積", "hs_math_2"),
                          _buildOfficialTextCard("高校数学 II 発展", "指数・対数関数", "hs_math_2_advanced"),
                          _buildOfficialTextCard("高校数学 B", "数列", "hs_math_b"),
                          _buildOfficialTextCard("高校数学 B 発展", "統計的推測", "hs_math_b_advanced"),
                          _buildOfficialTextCard("高校数学 III", "極限", "hs_math_3"),
                          _buildOfficialTextCard("高校数学 III 発展", "複素数平面", "hs_math_3_advanced"),
                          _buildOfficialTextCard("高校数学 C", "ベクトル", "hs_math_c"),
                          _buildOfficialTextCard("高校数学 C 発展", "行列・式と曲線", "hs_math_c_advanced"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("英語", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.language, color: Colors.red),
                        children: [
                          _buildOfficialTextCard("高校英語 総合文法", "仮定法・関係詞", "hs_eng_grammar"),
                          _buildOfficialTextCard("高校英語 長文読解", "論説文の読み方", "hs_eng_reading"),
                          _buildOfficialTextCard("高校英語 英作文", "和文英訳・自由英作文", "hs_eng_composition"),
                          _buildOfficialTextCard("高校英語 英文解釈", "構文解析", "hs_eng_interpretation"),
                          _buildOfficialTextCard("高校英語 リスニング", "聞き取り対策", "hs_eng_listening"),
                          _buildOfficialTextCard("高校英単語 ターゲット1900", "基本単語", "hs_eng_vocab"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("理科", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.science, color: Colors.green),
                        children: [
                          _buildOfficialTextCard("高校物理 Vol.1", "力学・波動", "hs_science_physics"),
                          _buildOfficialTextCard("高校物理 Vol.2", "電磁気学", "hs_science_physics_v2"),
                          _buildOfficialTextCard("高校物理 Vol.3", "熱力学", "hs_science_physics_v3"),
                          _buildOfficialTextCard("高校物理 Vol.4", "原子物理", "hs_science_physics_v4"),
                          _buildOfficialTextCard("高校化学 Vol.1", "物質の構成・変化", "hs_science_chem"),
                          _buildOfficialTextCard("高校化学 Vol.2", "化学平衡・反応速度", "hs_science_chem_v2"),
                          _buildOfficialTextCard("高校化学 Vol.3", "有機化学", "hs_science_chem_v3"),
                          _buildOfficialTextCard("高校化学 Vol.4", "無機化学", "hs_science_chem_v4"),
                          _buildOfficialTextCard("高校生物 Vol.1", "細胞と分子", "hs_science_bio"),
                          _buildOfficialTextCard("高校生物 Vol.2", "遺伝", "hs_science_bio_v2"),
                          _buildOfficialTextCard("高校生物 Vol.3", "進化", "hs_science_bio_v3"),
                          _buildOfficialTextCard("高校生物 Vol.4", "生態系", "hs_science_bio_v4"),
                          _buildOfficialTextCard("高校地学 Vol.1", "地球の概観", "hs_science_earth"),
                          _buildOfficialTextCard("高校地学 Vol.2", "気象・海洋", "hs_science_earth_v2"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("社会", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.public, color: Colors.orange),
                        children: [
                          _buildOfficialTextCard("高校世界史 Vol.1", "市民革命・産業革命", "hs_social_world_history"),
                          _buildOfficialTextCard("高校世界史 Vol.2", "古代文明", "hs_social_world_history_v2"),
                          _buildOfficialTextCard("高校世界史 Vol.3", "中世ヨーロッパ", "hs_social_world_history_v3"),
                          _buildOfficialTextCard("高校世界史 Vol.4", "近現代史", "hs_social_world_history_v4"),
                          _buildOfficialTextCard("高校日本史 Vol.1", "幕藩体制の確立", "hs_social_japan_history"),
                          _buildOfficialTextCard("高校日本史 Vol.2", "古代〜平安時代", "hs_social_japan_history_v2"),
                          _buildOfficialTextCard("高校日本史 Vol.3", "鎌倉〜室町時代", "hs_social_japan_history_v3"),
                          _buildOfficialTextCard("高校日本史 Vol.4", "明治以降", "hs_social_japan_history_v4"),
                          _buildOfficialTextCard("高校地理 Vol.1", "地図と地理情報", "hs_social_geography"),
                          _buildOfficialTextCard("高校地理 Vol.2", "系統地理", "hs_social_geography_v2"),
                          _buildOfficialTextCard("高校公民", "青年期・経済社会", "hs_social_civics"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("国語", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.menu_book, color: Colors.purple),
                        children: [
                          _buildOfficialTextCard("高校国語 現代文 Vol.1", "評論文の読解", "hs_japanese_modern_v1"),
                          _buildOfficialTextCard("高校国語 現代文 Vol.2", "小説の読解", "hs_japanese_modern_v2"),
                          _buildOfficialTextCard("高校国語 古文 Vol.1", "古典文法（動詞・形容詞）", "hs_japanese_classical_v1"),
                          _buildOfficialTextCard("高校国語 古文 Vol.2", "古典文法（助動詞）", "hs_japanese_classical_v2"),
                          _buildOfficialTextCard("高校国語 漢文 Vol.1", "漢文句法", "hs_japanese_kanbun_v1"),
                          _buildOfficialTextCard("高校国語 漢文 Vol.2", "漢詩", "hs_japanese_kanbun_v2"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("実技科目", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("音楽", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.music_note, color: Colors.pink),
                        children: [
                          _buildOfficialTextCard("音楽 楽典", "楽譜の読み方", "music_theory"),
                          _buildOfficialTextCard("音楽 音楽史", "西洋音楽史", "music_history"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("美術", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.palette, color: Colors.deepOrange),
                        children: [
                          _buildOfficialTextCard("美術 美術史", "西洋美術史", "art_history"),
                          _buildOfficialTextCard("美術 技法", "絵画技法", "art_technique"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("保健体育", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.sports_soccer, color: Colors.teal),
                        children: [
                          _buildOfficialTextCard("保健体育 保健", "健康な生活", "health"),
                          _buildOfficialTextCard("保健体育 体育理論", "スポーツの意義", "pe_theory"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("技術・家庭", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.build, color: Colors.brown),
                        children: [
                          _buildOfficialTextCard("技術・家庭 技術分野", "材料と加工", "technology"),
                          _buildOfficialTextCard("技術・家庭 家庭分野", "食生活", "home_economics"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("大学受験", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("共通テスト対策", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.school, color: Colors.indigo),
                        children: [
                          _buildOfficialTextCard("共通テスト対策 数学", "攻略法", "common_test_math"),
                          _buildOfficialTextCard("共通テスト対策 英語", "攻略法", "common_test_english"),
                          _buildOfficialTextCard("共通テスト対策 国語", "攻略法", "common_test_japanese"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("二次試験対策", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.edit_note, color: Colors.deepPurple),
                        children: [
                          _buildOfficialTextCard("二次試験対策 数学", "記述式", "secondary_exam_math"),
                          _buildOfficialTextCard("二次試験対策 英語", "記述式", "secondary_exam_english"),
                          _buildOfficialTextCard("小論文対策", "書き方", "essay_writing"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("資格試験", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("英検", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                        children: [
                          _buildOfficialTextCard("英検3級対策", "中学卒業レベル", "eiken_3"),
                          _buildOfficialTextCard("英検準2級対策", "高校中級レベル", "eiken_pre2"),
                          _buildOfficialTextCard("英検2級対策", "高校卒業レベル", "eiken_2"),
                          _buildOfficialTextCard("英検準1級対策", "大学中級レベル", "eiken_pre1"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("その他検定", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.verified, color: Colors.cyan),
                        children: [
                          _buildOfficialTextCard("数学検定対策", "級別対策", "suken"),
                          _buildOfficialTextCard("漢字検定対策", "級別対策", "kanken"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("プログラミング・情報", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("プログラミング", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.computer, color: Colors.blueGrey),
                        children: [
                          _buildOfficialTextCard("プログラミング入門 Scratch", "ブロックプログラミング", "programming_scratch"),
                          _buildOfficialTextCard("プログラミング入門 Python", "テキストプログラミング", "programming_python"),
                          _buildOfficialTextCard("高校 情報I", "情報社会・アルゴリズム", "programming_info1"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("英語4技能 発展", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("4技能強化", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.record_voice_over, color: Colors.redAccent),
                        children: [
                          _buildOfficialTextCard("英語 スピーキング対策", "音読・シャドーイング", "eng_speaking"),
                          _buildOfficialTextCard("英語 ライティング発展", "パラグラフライティング", "eng_writing_advanced"),
                          _buildOfficialTextCard("英語 発音・アクセント", "発音の基礎", "eng_pronunciation"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("オリンピック対策", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("科学オリンピック", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.emoji_events, color: Colors.yellow),
                        children: [
                          _buildOfficialTextCard("数学オリンピック対策", "整数問題", "math_olympiad"),
                          _buildOfficialTextCard("物理オリンピック対策", "力学の応用", "physics_olympiad"),
                          _buildOfficialTextCard("化学オリンピック対策", "反応速度論", "chemistry_olympiad"),
                          _buildOfficialTextCard("生物オリンピック対策", "分子生物学", "biology_olympiad"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("実用スキル", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("学習・発表スキル", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.lightbulb, color: Colors.orangeAccent),
                        children: [
                          _buildOfficialTextCard("プレゼンテーション技法", "構成・スライド作成", "presentation"),
                          _buildOfficialTextCard("レポート・論文の書き方", "レポートの構成", "report_writing"),
                          _buildOfficialTextCard("ノート術・勉強法", "効果的な勉強法", "study_methods"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("その他資格試験", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("英語資格", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.card_membership, color: Colors.lightBlue),
                        children: [
                          _buildOfficialTextCard("TOEIC対策", "リスニング・リーディング", "toeic"),
                          _buildOfficialTextCard("TOEFL対策", "4技能総合", "toefl"),
                          _buildOfficialTextCard("GTEC対策", "4技能", "gtec"),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text("発展・専門", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ExpansionTile(
                        title: const Text("数学 発展", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.functions, color: Colors.deepPurple),
                        children: [
                          _buildOfficialTextCard("微分積分 発展", "多変数関数", "advanced_calculus"),
                          _buildOfficialTextCard("線形代数", "ベクトル空間", "linear_algebra"),
                          _buildOfficialTextCard("確率統計 発展", "確率分布", "probability_stats"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("理科 発展", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.biotech, color: Colors.lightGreen),
                        children: [
                          _buildOfficialTextCard("量子力学入門", "量子の世界", "quantum_physics"),
                          _buildOfficialTextCard("有機化学 発展", "反応機構", "organic_chem_advanced"),
                          _buildOfficialTextCard("分子生物学 発展", "遺伝子発現制御", "molecular_biology"),
                        ],
                      ),
                      ExpansionTile(
                        title: const Text("人文科学", style: TextStyle(fontWeight: FontWeight.bold)),
                        leading: const Icon(Icons.auto_stories, color: Colors.brown),
                        children: [
                          _buildOfficialTextCard("世界文学", "西洋文学", "world_literature"),
                          _buildOfficialTextCard("哲学入門", "西洋哲学史", "philosophy"),
                          _buildOfficialTextCard("経済学入門", "ミクロ経済学", "economics"),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'library_upload_fab',
          onPressed: _uploadMaterial,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildOfficialTextCard(String title, String subtitle, String textId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: const Icon(Icons.book, size: 40, color: Colors.orange),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OfficialTextScreen(textId: textId, title: title),
              ),
            );
          },
          icon: const Icon(Icons.menu_book, size: 16),
          label: const Text("開く"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}


class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _selectedGrade = '中学2年生';
  String _selectedPersona = 'gentle';
  final TextEditingController _goalController = TextEditingController();
  final TextEditingController _interestsController = TextEditingController();
  String _selectedAvatar = 'default'; // default, boy, girl
  bool _isLoading = false;

  final List<String> _grades = [
    '中学1年生', '中学2年生', '中学3年生',
    '高校1年生', '高校2年生', '高校3年生',
    '大学生', '社会人'
  ];

  final Map<String, String> _personas = {
    'gentle': '優しい先生（褒めて伸びる）',
    'hot_blooded': '熱血コーチ（厳しく鼓舞）',
    'strict': '厳格な教授（論理的）',
  };

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('$backendUrl/profile/demo_user'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['grade'] != null && _grades.contains(data['grade'])) {
          setState(() => _selectedGrade = data['grade']);
        }
        if (data['persona'] != null) setState(() => _selectedPersona = data['persona']);
        if (data['goal'] != null) _goalController.text = data['goal'];
        if (data['interests'] != null) _interestsController.text = data['interests'];
        if (data['avatar'] != null) setState(() => _selectedAvatar = data['avatar']);
      }
    } catch (e) {
      print('Error fetching profile: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/update_profile'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'grade': _selectedGrade,
          'persona': _selectedPersona,
          'goal': _goalController.text,
          'interests': _interestsController.text,
          'avatar': _selectedAvatar,
        }),
      );
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロフィールを保存しました')),
        );
      } else {
        throw Exception('Failed to update profile');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラーが発生しました: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール設定')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar Selection
                  Center(
                    child: Column(
                      children: [
                        const Text("アバター選択", style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildAvatarOption('default', Icons.person),
                            const SizedBox(width: 16),
                            _buildAvatarOption('boy', Icons.face), // Placeholder icons until images are ready
                            const SizedBox(width: 16),
                            _buildAvatarOption('girl', Icons.face_3),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Grade
                  const Text("学年", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedGrade,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _grades.map((grade) {
                      return DropdownMenuItem(value: grade, child: Text(grade));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedGrade = value);
                    },
                  ),
                  const SizedBox(height: 24),

                  // Goal
                  const Text("目標・志望校", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '例: 〇〇高校合格、英検2級',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Interests
                  const Text("興味・好きなこと（AIが例え話に使います）", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _interestsController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '例: サッカー、ゲーム、料理',
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Teaching Style (Persona)
                  const Text("AI先生の性格", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedPersona,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _personas.entries.map((entry) {
                      return DropdownMenuItem(value: entry.key, child: Text(entry.value));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedPersona = value);
                    },
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("保存する", style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarOption(String key, IconData icon) {
    final isSelected = _selectedAvatar == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedAvatar = key),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: 2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 40, color: isSelected ? Colors.blue : Colors.grey),
      ),
    );
  }

  void _addToCalendar(String title, String description) {
    final Event event = Event(
      title: title,
      description: description,
      location: '自宅',
      startDate: DateTime.now().add(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1, hours: 1)),
      iosParams: const IOSParams(reminder: Duration(minutes: 10)),
    );
    Add2Calendar.addEvent2Cal(event);
  }
}



