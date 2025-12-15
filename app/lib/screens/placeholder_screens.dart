import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants.dart';
import '../services/auth_service.dart';

// ---------------------------------------------------------------------------
// Settings Screen (with Logout)
// ---------------------------------------------------------------------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ログアウト"),
        content: const Text("本当にログアウトしますか？"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("キャンセル")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("ログアウト", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await authService.signOut();
      // AuthWrapper will handle navigation
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: ListView(
        children: [
          const UserAccountsDrawerHeader(
            accountName: Text("User"),
            accountEmail: Text("user@example.com"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.grey),
            ),
            decoration: BoxDecoration(color: Color(0xFF6C63FF)),
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text("通知設定"),
            trailing: Switch(value: true, onChanged: (v) {}),
          ),
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text("音声設定"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
           ListTile(
            leading: const Icon(Icons.color_lens),
            title: const Text("テーマ設定"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help),
            title: const Text("ヘルプ・サポート"),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text("アプリについて"),
            onTap: () {},
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("ログアウト", style: TextStyle(color: Colors.red)),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lecture Screen (Class Recorder Implementation)
// ---------------------------------------------------------------------------
class LectureScreen extends StatefulWidget {
  const LectureScreen({super.key});

  @override
  State<LectureScreen> createState() => _LectureScreenState();
}

class _LectureScreenState extends State<LectureScreen> {
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
      } else {
         if (!mounted) return;
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('マイクの権限が必要です')));
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
        if (!mounted) return;
        setState(() {
          _result = jsonDecode(respStr);
        });
      } else {
         throw Exception("Failed to summarize class");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
       appBar: AppBar(title: const Text("授業レコーダー")),
       body: SafeArea(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: _result == null
               ? Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       GestureDetector(
                         onTap: _toggleRecording,
                         child: Container(
                           padding: const EdgeInsets.all(40), // Increased button size slightly
                           decoration: BoxDecoration(
                             color: _isRecording ? Colors.red : const Color(0xFF6C63FF), // Use theme color
                             shape: BoxShape.circle,
                             boxShadow: const [
                               BoxShadow(
                                 color: Colors.black26, 
                                 blurRadius: 20, 
                                 offset: Offset(0, 10)
                               )
                             ],
                           ),
                           child: Icon(
                             _isRecording ? Icons.stop : Icons.mic, 
                             color: Colors.white, 
                             size: 64
                           ),
                         ),
                       ),
                       const SizedBox(height: 48),
                       Text(
                         _isProcessing ? "AIが授業を分析中..." : (_isRecording ? "録音中..." : "タップして録音開始"),
                         style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                       ),
                       const SizedBox(height: 16),
                       const Text(
                         "授業の音声をAIが自動で要約し、\n復習ポイントをリストアップします。", 
                         textAlign: TextAlign.center, 
                         style: TextStyle(color: Colors.grey, fontSize: 16)
                       ),
                     ],
                   ),
                 )
               : Column(
                   children: [
                     Expanded(
                       child: ListView(
                         padding: const EdgeInsets.only(bottom: 80),
                         children: [
                           const Text("要約", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                           const SizedBox(height: 8),
                           Container(
                             padding: const EdgeInsets.all(16),
                             decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                             child: Text(_result!['summary'] ?? ""),
                           ),
                           const Divider(height: 32),
                           const Text("重要キーワード", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                           const SizedBox(height: 8),
                           Wrap(
                             spacing: 8,
                             runSpacing: 8,
                             children: List<String>.from(_result!['keywords'] ?? []).map((k) => Chip(
                               label: Text(k),
                               backgroundColor: Colors.blue.withOpacity(0.1),
                               labelStyle: const TextStyle(color: Colors.blue),
                             )).toList(),
                           ),
                           const Divider(height: 32),
                           const Text("復習クイズ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                           ...List<dynamic>.from(_result!['quiz'] ?? []).map((q) => Card(
                             margin: const EdgeInsets.symmetric(vertical: 8),
                             elevation: 2,
                             child: ExpansionTile(
                               title: Text(q['question'] ?? "", style: const TextStyle(fontWeight: FontWeight.w600)),
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
                     SizedBox(
                       width: double.infinity,
                       child: ElevatedButton.icon(
                         onPressed: () => setState(() => _result = null),
                         icon: const Icon(Icons.refresh),
                         label: const Text("新しく録音する"),
                         style: ElevatedButton.styleFrom(
                           padding: const EdgeInsets.symmetric(vertical: 16),
                           backgroundColor: const Color(0xFF6C63FF),
                           foregroundColor: Colors.white,
                         ),
                       ),
                     ),
                   ],
                 ),
         ),
       ),
     );
  }
}

// ---------------------------------------------------------------------------
// Roadmap Screen
// ---------------------------------------------------------------------------
class RoadmapScreen extends StatelessWidget {
  const RoadmapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("学習ロードマップ")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
           _buildRoadmapItem("Goal: 志望校合格", "詳細な目標設定を完了しよう", Icons.flag, true, true),
           _buildRoadmapItem("基礎固め (現在地)", "英単語ターゲット1200\n数学I・A 青チャート", Icons.foundation, true, false),
           _buildRoadmapItem("応用力養成", "夏休み明けまでに開始予定", Icons.trending_up, false, false),
           _buildRoadmapItem("過去問演習", "11月開始予定", Icons.edit_document, false, false),
        ],
      ),
    );
  }

  Widget _buildRoadmapItem(String title, String subtitle, IconData icon, bool isActive, bool isCompleted) {
    return Card(
      color: isActive ? Colors.white : Colors.grey[100],
      child: ListTile(
        leading: Icon(icon, color: isActive ? Colors.blue : Colors.grey, size: 32),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black87 : Colors.grey)),
        subtitle: Text(subtitle),
        trailing: isCompleted ? const Icon(Icons.check_circle, color: Colors.green) : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics Screen
// ---------------------------------------------------------------------------
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("学習分析")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
             Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text("今週の学習時間", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  const titles = ['月', '火', '水', '木', '金', '土', '日'];
                                  if (value.toInt() < titles.length) {
                                    return Text(titles[value.toInt()]);
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          gridData: const FlGridData(show: false),
                          barGroups: [
                            _makeGroupData(0, 2),
                            _makeGroupData(1, 4),
                            _makeGroupData(2, 3),
                            _makeGroupData(3, 1),
                            _makeGroupData(4, 5),
                            _makeGroupData(5, 2),
                            _makeGroupData(6, 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
             ),
             const SizedBox(height: 16),
             Row(
               children: [
                 Expanded(child: _buildStatCard("合計学習時間", "124時間", Colors.blue)),
                 const SizedBox(width: 16),
                 Expanded(child: _buildStatCard("解決した問題", "342問", Colors.orange)),
               ],
             ),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _makeGroupData(int x, double y) {
    return BarChartGroupData(x: x, barRods: [BarChartRodData(toY: y, color: Colors.blue, width: 16, borderRadius: BorderRadius.circular(4))]);
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Exam Planner Screen
// ---------------------------------------------------------------------------
class ExamPlannerScreen extends StatelessWidget {
  const ExamPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("試験・目標管理")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildExamItem("第2回 定期テスト", "2024/05/20", "あと14日", Colors.redAccent),
          _buildExamItem("英語検定 2級", "2024/06/02", "あと27日", Colors.orange),
          _buildExamItem("全国模試", "2024/07/15", "あと2ヶ月", Colors.blue),
          
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text("試験予定を追加"),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamItem(String title, String date, String remaining, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.2), child: Icon(Icons.event, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(date),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Text(remaining, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
