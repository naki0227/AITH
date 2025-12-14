// Learning-related screens grouped together
// This file contains screens for official texts and practice drills

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants.dart';
import '../utils/latex_syntax.dart';
import '../utils/latex_builder.dart';

// OfficialTextScreen - displays official curriculum texts
class OfficialTextScreen extends StatefulWidget {
  final String textId;
  final String title;

  const OfficialTextScreen({super.key, required this.textId, required this.title});

  @override
  State<OfficialTextScreen> createState() => _OfficialTextScreenState();
}

class _OfficialTextScreenState extends State<OfficialTextScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _textData;

  @override
  void initState() {
    super.initState();
    _fetchTextData();
  }

  Future<void> _fetchTextData() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/official_texts/${widget.textId}'));
      if (response.statusCode == 200) {
        setState(() {
          _textData = jsonDecode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load text');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printText() async {
    if (_textData == null) return;
    
    final chapters = _textData!['chapters'] as List;
    String fullContent = "";
    for (var chapter in chapters) {
      fullContent += "${chapter['content']}\n\n";
    }

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansJPRegular();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font),
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text(widget.title, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
            pw.Paragraph(text: fullContent),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _printText,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _textData == null
              ? const Center(child: Text("読み込みエラー"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: (_textData!['chapters'] as List).length,
                  itemBuilder: (context, index) {
                    final chapter = _textData!['chapters'][index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 24),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chapter['title'], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
                            const Divider(),
                            MarkdownBody(data: chapter['content']),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// DrillScreen - practice drill questions with scoring
class DrillScreen extends StatefulWidget {
  final List<dynamic> questions;
  final String subject; // Pass subject

  const DrillScreen({super.key, required this.questions, required this.subject});

  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  int _currentIndex = 0;
  int _score = 0;
  bool _isAnswered = false;
  int? _selectedOption;
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

  
  // Actually, let's refactor _checkAnswer and state to track answers
  final Map<int, int> _userAnswers = {}; // index -> selectedOption

  void _checkAnswer(int index) {
    setState(() {
      _selectedOption = index;
      _isAnswered = true;
      _userAnswers[_currentIndex] = index;
      if (index == widget.questions[_currentIndex]['answer_index']) {
        _score++;
      }
    });
  }

  Future<void> _finishDrill() async {
    _stopwatch.stop();
    final durationSeconds = _stopwatch.elapsed.inSeconds;

    // Identify mistakes
    List<Map<String, dynamic>> mistakes = [];
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final userAnswer = _userAnswers[i];
      if (userAnswer != null && userAnswer != q['answer_index']) {
        mistakes.add({
          'question': q['question'],
          'options': q['options'],
          'answer_index': q['answer_index'],
          'explanation': q['explanation'],
          'subject': widget.subject,
        });
      }
    }

    // Send log & mistakes to backend
    try {
      // 1. Log
      await http.post(
        Uri.parse('$backendUrl/record_study_log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'type': 'drill',
          'subject': widget.subject,
          'duration_seconds': durationSeconds,
          'score': _score,
          'total_questions': widget.questions.length,
        }),
      );

      // 2. Register Mistakes
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

    // Show result
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("ドリル終了！🎉"),
        content: Text("あなたのスコアは $_score / ${widget.questions.length} です！\n学習時間: ${durationSeconds}秒\n\n間違えた問題は「復習帳」に登録されました。"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close screen
            },
            child: const Text("ライブラリに戻る"),
          ),
        ],
      ),
    );
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _isAnswered = false;
        _selectedOption = null;
      });
    } else {
      _finishDrill();
    }
  }

  Widget _buildMarkdown(String text) {
     // Re-use the existing markdown builder logic or create a helper
     // For simplicity, we'll instantiate MarkdownBody directly here, 
     // but ideally we should expose the helper from ChatScreen or make it global.
     // Since _autoFixLatex is in ChatScreen, we'll duplicate the simple logic or make it static.
     // Let's make a simple static helper for now.
     return MarkdownBody(
        data: _simpleAutoFixLatex(text),
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

  String _simpleAutoFixLatex(String text) {
     // Duplicate of _autoFixLatex logic for now
    text = text.replaceAllMapped(
      RegExp(r'(?<!\\$|\\\\)(\\\\[a-zA-Z]+(?:\\s*\\{(?:[^{}]|\\{[^{}]*\\})*\\})*)'), 
      (match) => '\$${match.group(1)}\$',
    );
    text = text.replaceAllMapped(
      RegExp(r'(?<!\\$)\\b([a-zA-Z0-9]+\\^[a-zA-Z0-9]+)\\b'),
      (match) => '\$${match.group(1)}\$',
    );
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final questionData = widget.questions[_currentIndex];
    final options = List<String>.from(questionData['options']);
    final answerIndex = questionData['answer_index'];
    final explanation = questionData['explanation'];

    return Scaffold(
      appBar: AppBar(title: Text("問題 ${_currentIndex + 1} / ${widget.questions.length}")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMarkdown(questionData['question']),
            const SizedBox(height: 24),
            ...List.generate(options.length, (index) {
              Color? tileColor;
              if (_isAnswered) {
                if (index == answerIndex) {
                  tileColor = Colors.green[100];
                } else if (index == _selectedOption) {
                  tileColor = Colors.red[100];
                }
              }

              return Card(
                color: tileColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: _buildMarkdown(options[index]),
                  leading: _isAnswered
                      ? (index == answerIndex
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (index == _selectedOption
                              ? const Icon(Icons.cancel, color: Colors.red)
                              : null))
                      : CircleAvatar(child: Text("${index + 1}")),
                  onTap: _isAnswered ? null : () => _checkAnswer(index),
                ),
              );
            }),
            const Spacer(),
            if (_isAnswered) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("解説", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _buildMarkdown(explanation),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextQuestion,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_currentIndex < widget.questions.length - 1 ? "次の問題へ" : "結果を見る"),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
