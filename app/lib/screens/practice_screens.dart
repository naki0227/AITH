// Practice-related screens grouped together
// This file contains screens for flashcards, review, and essay correction

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import 'learning_screens.dart';  // For DrillScreen reference

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _fetchDueReviews();
  }

  Future<void> _fetchDueReviews() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/due_reviews/demo_user'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _items = data['items'];
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Fetch reviews error: $e");
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submitReview(int quality) async {
    final item = _items[_currentIndex];
    try {
      await http.post(
        Uri.parse('$backendUrl/update_review_status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'item_id': item['item_id'],
          'quality': quality
        }),
      );
      
      setState(() {
        if (_currentIndex < _items.length - 1) {
          _currentIndex++;
          _showBack = false;
        } else {
          // Finished
          _items = [];
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  void _showDrillDialog() {
    final TextEditingController topicController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("無限ドリルを開始"),
        content: TextField(
          controller: topicController,
          decoration: const InputDecoration(labelText: "トピック（例: 中2数学 連立方程式）"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("キャンセル")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (topicController.text.isNotEmpty) {
                _startDrill(topicController.text);
              }
            },
            child: const Text("開始"),
          ),
        ],
      ),
    );
  }

  Future<void> _startDrill(String topic) async {
    setState(() => _isLoading = true);
    try {
      // Use the same endpoint as LibraryScreen but with direct topic
      // Note: LibraryScreen uses material_id, but we want topic-based.
      // We might need to adjust backend or use a different param.
      // Checking backend... generate_drill accepts (topic, grade) OR (material_id).
      // Let's check backend/main.py again.
      
      // Actually, let's use the existing _generateContent logic from HomeScreen which calls generate_drill with topic/grade.
      // Or simply call /generate_drill with topic if supported.
      // Looking at backend: generate_drill(request: DrillRequest) where DrillRequest has material_id OR (topic AND grade).
      
      final response = await http.post(
        Uri.parse('$backendUrl/generate_drill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'topic': topic,
          'grade': '中学生', // Default or ask user
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
                subject: topic,
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
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("究極の復習")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.green),
              const SizedBox(height: 24),
              const Text("現在、復習する項目はありません！\n素晴らしい進捗です。", textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("戻る"),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'review_empty_fab',
          onPressed: _showDrillDialog,
          label: const Text("無限ドリル"),
          icon: const Icon(Icons.quiz),
        ),
      );
    }

    final item = _items[_currentIndex];
    final content = jsonDecode(item['content']); // Assuming content is JSON string

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'review_fab',
        onPressed: _showDrillDialog,
        label: const Text("無限ドリル"),
        icon: const Icon(Icons.quiz),
      ),
      appBar: AppBar(title: Text("復習 (${_currentIndex + 1}/${_items.length})")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => setState(() => _showBack = !_showBack),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _showBack ? "答え" : "問題",
                          style: const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _showBack ? content['back'] : content['front'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        if (!_showBack)
                          const Text("タップして答えを表示", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ).animate(target: _showBack ? 1 : 0).flipH(duration: 300.ms),
                ),
              ),
            ),
            if (_showBack) ...[
              const SizedBox(height: 24),
              const Text("自己評価", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildQualityButton("全然", 0, Colors.red),
                  _buildQualityButton("難しい", 2, Colors.orange),
                  _buildQualityButton("普通", 3, Colors.blue),
                  _buildQualityButton("簡単", 5, Colors.green),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQualityButton(String label, int quality, Color color) {
    return ElevatedButton(
      onPressed: () => _submitReview(quality),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }
}

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  final TextEditingController _subjectController = TextEditingController();
  List<dynamic> _cards = [];
  bool _isLoading = false;
  int _currentIndex = 0;
  bool _showBack = false;

  Future<void> _generateCards() async {
    if (_subjectController.text.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/generate_flashcards'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': 'demo_user', 'subject': _subjectController.text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _cards = data['cards'];
          _currentIndex = 0;
          _showBack = false;
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
      appBar: AppBar(title: const Text("自動単語帳")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_cards.isEmpty) ...[
              const Icon(Icons.style, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text("覚えたい分野を入力してください\nAIが単語カードを作成します！", textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              const SizedBox(height: 32),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '分野（例: 英単語、歴史年号、理科用語）',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _generateCards,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("カードを作成する", style: TextStyle(fontSize: 18)),
                ),
              ),
            ] else ...[
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _showBack = !_showBack),
                    child: Container(
                      width: 300,
                      height: 400,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: const Offset(0, 8))],
                        border: Border.all(color: Colors.orange.shade100, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _showBack ? "答え" : "問題",
                            style: const TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _showBack ? _cards[_currentIndex]['back'] : _cards[_currentIndex]['front'],
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 24),
                          if (_showBack)
                            const Text("タップして問題に戻る", style: TextStyle(color: Colors.grey))
                          else
                            const Text("タップして答えを見る", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ).animate(target: _showBack ? 1 : 0).flipH(duration: 300.ms),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _currentIndex > 0 ? () => setState(() { _currentIndex--; _showBack = false; }) : null,
                    child: const Text("前へ"),
                  ),
                  Text("${_currentIndex + 1} / ${_cards.length}"),
                  ElevatedButton(
                    onPressed: _currentIndex < _cards.length - 1 ? () => setState(() { _currentIndex++; _showBack = false; }) : null,
                    child: const Text("次へ"),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() { _cards = []; _subjectController.clear(); }),
                child: const Text("新しいカードを作る"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StudyRoomScreen extends StatefulWidget {
  const StudyRoomScreen({super.key});

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  List<dynamic> _users = [];
  Timer? _timer;
  int _seconds = 0;
  bool _isStudying = false;

  @override
  void initState() {
    super.initState();
    _enterRoom();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isStudying) {
        setState(() => _seconds++);
      }
      if (timer.tick % 10 == 0) { // Refresh users every 10s
        _fetchUsers();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _enterRoom() async {
    try {
      await http.post(
        Uri.parse('$backendUrl/enter_study_room'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': 'demo_user', 'username': 'User'}),
      );
      setState(() => _isStudying = true);
      _fetchUsers();
    } catch (e) {
      print("Enter room error: $e");
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/study_room_users'));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _users = data['users'];
        });
      }
    } catch (e) {
      print("Fetch users error: $e");
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds / 60).floor().toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("バーチャル自習室")),
      body: Column(
        children: [
          // Timer Area
          Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Text("勉強時間", style: TextStyle(fontSize: 16, color: Colors.grey)),
                Text(_formatTime(_seconds), style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.indigo)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _isStudying = !_isStudying);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStudying ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_isStudying ? "休憩する" : "再開する"),
                ),
              ],
            ),
          ),
          const Divider(),
          // Users List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user['username']),
                  subtitle: Text(user['status'] ?? 'studying'),
                  trailing: const Icon(Icons.circle, color: Colors.green, size: 12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class EssayCorrectionScreen extends StatefulWidget {
  const EssayCorrectionScreen({super.key});

  @override
  State<EssayCorrectionScreen> createState() => _EssayCorrectionScreenState();
}

class _EssayCorrectionScreenState extends State<EssayCorrectionScreen> {
  final TextEditingController _textController = TextEditingController();
  File? _selectedImage;
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedImage = File(pickedFile.path));
    }
  }

  Future<void> _correctEssay() async {
    if (_textController.text.isEmpty && _selectedImage == null) return;
    
    setState(() => _isLoading = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/correct_essay'));
      if (_textController.text.isNotEmpty) {
        request.fields['text'] = _textController.text;
      }
      if (_selectedImage != null) {
        request.files.add(await http.MultipartFile.fromPath('image', _selectedImage!.path));
      }

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(respStr);
        setState(() {
          _result = data['result'];
        });
      } else {
        throw Exception('Failed to correct essay');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addToCalendar(String title, String description) {
    final Event event = Event(
      title: title,
      description: description,
      location: '自宅',
      startDate: DateTime.now().add(const Duration(hours: 1)),
      endDate: DateTime.now().add(const Duration(hours: 2)),
    );
    Add2Calendar.addEvent2Cal(event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI記述添削")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_result == null) ...[
              const Text("英作文や小論文を入力するか、写真をアップロードしてください。", style: TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: _textController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: "ここに文章を入力...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image),
                    label: const Text("画像を選択"),
                  ),
                  const SizedBox(width: 16),
                  if (_selectedImage != null)
                    const Text("画像選択済み", style: TextStyle(color: Colors.green)),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _correctEssay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("添削する", style: TextStyle(fontSize: 18)),
              ),
            ] else ...[
              // Result View
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("添削結果", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(20)),
                          child: Text("評価: ${_result!['grade']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    const Text("コメント", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_result!['comment']),
                    const SizedBox(height: 16),
                    const Text("添削後の文章", style: TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                      child: Text(_result!['corrected_text']),
                    ),
                    const SizedBox(height: 16),
                    const Text("詳細フィードバック", style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_result!['feedback'] != null && _result!['feedback'] is List)
                      ...List<dynamic>.from(_result!['feedback']).map((item) {
                        final theme = item['theme']?.toString() ?? 'No Theme';
                        final tasks = item['tasks'] is List ? (item['tasks'] as List).join('\n') : '';
                        return ListTile(
                          leading: const Icon(Icons.check_circle, color: Colors.teal),
                          title: Text(theme, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(tasks),
                          trailing: IconButton(
                            icon: const Icon(Icons.calendar_today, color: Colors.blue),
                            onPressed: () => _addToCalendar(theme, tasks),
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => setState(() { _result = null; _textController.clear(); _selectedImage = null; }),
                child: const Text("もう一度添削する"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ParentConnectScreen extends StatefulWidget {
  const ParentConnectScreen({super.key});

  @override
  State<ParentConnectScreen> createState() => _ParentConnectScreenState();
}

class _ParentConnectScreenState extends State<ParentConnectScreen> {
  bool _isLoading = false;
  String? _reportMessage;

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/generate_parent_report'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'period': 'weekly',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _reportMessage = data['report']['message'];
        });
      } else {
        throw Exception('Failed to generate report');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _shareReport() {
    if (_reportMessage != null) {
      Share.share(_reportMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("保護者レポート")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.family_restroom, size: 80, color: Colors.purple),
            const SizedBox(height: 24),
            const Text(
              "学習の成果を保護者の方に報告しましょう。\nAIが頑張りをまとめたメッセージを作成します。",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            if (_reportMessage == null)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _generateReport,
                icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.auto_awesome),
                label: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text("レポートを作成する"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            if (_reportMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade100),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("作成されたメッセージ:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                    const SizedBox(height: 8),
                    Text(_reportMessage!, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: 0.1, end: 0),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _shareReport,
                icon: const Icon(Icons.share),
                label: const Text("LINEなどで送る"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _reportMessage = null),
                child: const Text("作り直す"),
              ),
            ],
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text("学習相談・面談", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("塾講師経験のあるスタッフに学習の悩みを相談できます。", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final Uri url = Uri.parse('https://calendly.com/'); // Replace with actual booking URL
                if (!await launchUrl(url)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ブラウザを開けませんでした')),
                  );
                }
              },
              icon: const Icon(Icons.calendar_month),
              label: const Text("面談を申し込む"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
