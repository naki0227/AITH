// Communication-related screens grouped together
// This file contains screens for chat, voice tutor, and mock interview

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:record/record.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models/message.dart'; 
import '../utils/latex_syntax.dart';
import '../utils/latex_builder.dart';
import '../widgets/challenge_dialog.dart';

class MockInterviewScreen extends StatefulWidget {
  const MockInterviewScreen({super.key});

  @override
  State<MockInterviewScreen> createState() => _MockInterviewScreenState();
}

class _MockInterviewScreenState extends State<MockInterviewScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isRecording = false;
  bool _isProcessing = false;
  String _interviewType = "university_entrance";
  List<Map<String, String>> _history = [
    {"role": "ai", "text": "こんにちは。面接を始めます。まずは自己紹介をお願いします。"}
  ];

  @override
  void initState() {
    super.initState();
    _flutterTts.setLanguage("ja-JP");
    _speak(_history[0]['text']!);
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    await _flutterTts.speak(text);
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
        final path = '${directory.path}/interview_audio.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() => _isProcessing = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/mock_interview'));
      request.files.add(await http.MultipartFile.fromPath('file', path));
      request.fields['interview_type'] = _interviewType;

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(respStr);
        setState(() {
          _history.add({"role": "user", "text": "(音声回答)"});
          _history.add({"role": "ai", "text": data['reply']});
          if (data['feedback'] != null) {
             // Ideally show feedback separately or after interview
             print("Feedback: ${data['feedback']}");
          }
        });
        _speak(data['reply']);
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
      appBar: AppBar(title: const Text("AI面接官")),
      body: Column(
        children: [
          // Settings
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: DropdownButton<String>(
              value: _interviewType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: "university_entrance", child: Text("大学入試")),
                DropdownMenuItem(value: "job_hunting", child: Text("就職活動")),
              ],
              onChanged: (val) => setState(() => _interviewType = val!),
            ),
          ),
          // Chat History
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final msg = _history[index];
                final isAi = msg['role'] == 'ai';
                return Align(
                  alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAi ? Colors.grey[200] : Colors.blue[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(msg['text']!),
                  ),
                );
              },
            ),
          ),
          // Controls
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_isProcessing) const CircularProgressIndicator(),
                if (!_isProcessing)
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.blue,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 48),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(_isRecording ? "録音中..." : "タップして回答する", style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class VoiceTutorScreen extends StatefulWidget {
  const VoiceTutorScreen({super.key});

  @override
  State<VoiceTutorScreen> createState() => _VoiceTutorScreenState();
}

class _VoiceTutorScreenState extends State<VoiceTutorScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isRecording = false;
  bool _isProcessing = false;
  List<Map<String, String>> _conversation = []; // {sender: 'user'|'ai', text: '...'}

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        _processAudio(path);
      }
    } else {
      // Start recording
      if (await Permission.microphone.request().isGranted) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_input.m4a';
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('マイクの権限が必要です')));
      }
    }
  }

  Future<void> _processAudio(String path) async {
    setState(() => _isProcessing = true);
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/voice_chat'));
      request.files.add(await http.MultipartFile.fromPath('file', path));

      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(respStr);
        final reply = data['reply'];
        final correction = data['correction'];

        setState(() {
          _conversation.add({'sender': 'user', 'text': '(Audio Message)'}); // Placeholder
          _conversation.add({'sender': 'ai', 'text': reply});
          if (correction != null) {
            _conversation.add({'sender': 'ai', 'text': 'Correction: $correction', 'isCorrection': 'true'});
          }
        });

        // Speak reply
        await _flutterTts.speak(reply);
      } else {
        throw Exception('Voice chat failed');
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
      appBar: AppBar(title: const Text("英会話チューター")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _conversation.length,
              itemBuilder: (context, index) {
                final msg = _conversation[index];
                final isUser = msg['sender'] == 'user';
                final isCorrection = msg['isCorrection'] == 'true';
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue[100] : (isCorrection ? Colors.orange[100] : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text']!,
                      style: TextStyle(color: isCorrection ? Colors.deepOrange : Colors.black87),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isProcessing) const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: _toggleRecording,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text("タップして話す / 停止", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Message> _messages = []; // Removed final to allow reassignment
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  
  String _selectedMode = 'student'; // student, university, adult
  bool _isTyping = false;
  File? _draftImage; // Draft image
  http.Client? _httpClient; // For cancellation

  // Mode Display Names
  final Map<String, String> _modeNames = {
    'student': '中高生モード',
    'university': '大学生モード',
    'adult': '社会人モード',
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void deactivate() {
    _extractInsights();
    super.deactivate();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('chat_history');
    if (historyJson != null) {
      final List<dynamic> decoded = jsonDecode(historyJson);
      setState(() {
        _messages = decoded.map((item) => Message.fromJson(item)).toList();
      });
      // Scroll to bottom after build
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String historyJson = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await prefs.setString('chat_history', historyJson);
  }

  Future<void> _extractInsights() async {
    if (_messages.isEmpty) return;
    
    // Extract text from last 10 messages
    final recentMessages = _messages.reversed.take(10).toList().reversed;
    final text = recentMessages.map((m) => "${m.isUser ? 'User' : 'AI'}: ${m.text}").join("\n");

    try {
      await http.post(
        Uri.parse('$backendUrl/extract_insights'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': 'demo_user',
          'text': text,
        }),
      );
    } catch (e) {
      print('Insight extraction failed: $e');
    }
  }

  Future<void> _handleImageSelection(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _draftImage = File(image.path);
        });
      }
    } catch (e) {
      print('Error picking image: $e');
    }
  }

  Future<void> _sendMessage() async {
    // Cancel if generating
    if (_isTyping) {
      _httpClient?.close();
      setState(() {
        _isTyping = false;
        _messages.add(Message(
          text: "生成を中断しました。",
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
      return;
    }

    final text = _textController.text;
    final imagePath = _draftImage?.path;

    if (text.isEmpty && imagePath == null) return;

    setState(() {
      _messages.add(Message(
        text: text,
        isUser: true,
        imagePath: imagePath,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
      _draftImage = null; // Clear draft
    });
    _saveHistory(); // Save user message
    _scrollToBottom();
    _textController.clear();

    _httpClient = http.Client();

    try {
      if (imagePath != null) {
        await _sendImageAndText(imagePath, text);
      } else {
        await _sendText(text);
      }
    } catch (e) {
      if (e.toString().contains('ClientException')) {
         // Cancelled, do nothing or show message
      } else {
        setState(() {
          _messages.add(Message(
            text: "通信エラー: $e",
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTyping = false;
        });
        _saveHistory(); // Save AI response
        _scrollToBottom();
      }
      _httpClient = null;
    }
  }

  Future<void> _sendText(String text) async {
    var response = await _httpClient!.post(
      Uri.parse('$backendUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': text,
        'persona': globalPersona,
        'mode': _selectedMode,
      }),
    );
    _handleResponse(response);
  }

  Future<void> _sendImageAndText(String imagePath, String text) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$backendUrl/analyze_image'),
    );
    
    request.fields['mode'] = _selectedMode;
    if (text.isNotEmpty) {
      request.fields['text'] = text;
    }
    request.files.add(await http.MultipartFile.fromPath(
      'file', 
      imagePath,
      contentType: MediaType('image', 'jpeg'),
    ));

    var streamedResponse = await _httpClient!.send(request);
    var response = await http.Response.fromStream(streamedResponse);
    _handleResponse(response);
  }

  void _handleResponse(http.Response response) {
    if (response.statusCode == 200) {
      try {
        // 1. Attempt to decode JSON
        dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
        
        // Handle potential double-encoding (if backend returns a JSON string inside a string)
        if (decoded is String) {
          try {
            decoded = json.decode(decoded);
          } catch (e) {
            // It was just a string, keep it as is
          }
        }

        Map<String, dynamic> jsonResponse = {};
        if (decoded is Map<String, dynamic>) {
          jsonResponse = decoded;
        } else {
          // Unexpected format, treat as text
          throw FormatException("Response is not a JSON object");
        }

        List<dynamic>? blocks;
        if (jsonResponse.containsKey('blocks') && jsonResponse['blocks'] is List) {
          blocks = jsonResponse['blocks'];
        }

        Map<String, dynamic>? challenge;
        if (jsonResponse.containsKey('challenge') && jsonResponse['challenge'] is Map) {
          challenge = jsonResponse['challenge'];
        }
        
        // If no blocks found but we have a valid JSON object, maybe it's a flat text response?
        // But per schema, it should have blocks. 
        // If blocks is null, we fall back to displaying the raw text (or specific error).

        if (blocks != null) {
          setState(() {
            _messages.add(Message(
              text: '', 
              isUser: false,
              timestamp: DateTime.now(),
              challenge: challenge,
              blocks: blocks,
            ));
          });
        } else if (jsonResponse.containsKey('reply')) {
           setState(() {
            _messages.add(Message(
              text: jsonResponse['reply'],
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
        } else {
           // Fallback: Display raw body as text
           setState(() {
            _messages.add(Message(
              text: utf8.decode(response.bodyBytes),
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
        }

      } catch (e) {
        print("JSON Parse Error: $e");
        // Fallback: Display raw body as text
        setState(() {
          _messages.add(Message(
            text: utf8.decode(response.bodyBytes),
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } else {
      setState(() {
        _messages.add(Message(
          text: "エラーが発生しました: ${response.statusCode}",
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("学習モード設定", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ..._modeNames.entries.map((entry) => RadioListTile<String>(
                title: Text(entry.value),
                value: entry.key,
                groupValue: _selectedMode,
                onChanged: (value) {
                  setState(() {
                    _selectedMode = value!;
                  });
                  Navigator.pop(context);
                },
              )).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showChallengeDialog(Map<String, dynamic> challenge) {
    showDialog(
      context: context,
      builder: (context) {
        return ChallengeDialog(
          challenge: challenge,
          autoFixLatex: _autoFixLatex,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AITH Tutor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text("AIが入力中...", style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(message.imagePath!)),
                ),
              ),
            
            if (isUser)
              Text(
                message.text,
                style: const TextStyle(color: Colors.black87),
              )
            else
              _buildAiResponse(message),
            
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.timestamp),
              style: const TextStyle(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiResponse(Message message) {
    List<dynamic>? blocks = message.blocks;
    Map<String, dynamic>? challenge = message.challenge;

    // Try to parse text if blocks are missing (Fallback for raw JSON string)
    if (blocks == null && message.text.isNotEmpty) {
      try {
        String cleanText = message.text.trim();
        // Remove markdown code blocks
        if (cleanText.startsWith('```json')) {
          cleanText = cleanText.substring(7);
        } else if (cleanText.startsWith('```')) {
          cleanText = cleanText.substring(3);
        }
        if (cleanText.endsWith('```')) {
          cleanText = cleanText.substring(0, cleanText.length - 3);
        }
        
        dynamic decoded = jsonDecode(cleanText);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('blocks')) {
            blocks = decoded['blocks'];
          }
          if (decoded.containsKey('challenge')) {
            challenge = decoded['challenge'];
          }
        }
      } catch (e) {
        // Parse failed, blocks remains null
      }
    }

    if (blocks != null) {
      return SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBlockContent(blocks),
            if (challenge != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  onPressed: () => _showChallengeDialog(challenge!),
                  icon: const Icon(Icons.local_fire_department, color: Colors.white),
                  label: const Text("類題に挑戦する", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      );
    } else {
      // Fallback: Render as Markdown text
      return SelectionArea(
        child: MarkdownBody(
          data: _autoFixLatex(message.text),
          selectable: false, // Changed to false
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.black87),
          ),
          inlineSyntaxes: [LatexSyntax()],
          builders: {
            'latex': LatexElementBuilder(),
          },
        ),
      );
    }
  }

  Widget _buildBlockContent(List<dynamic> blocks) {
    List<Widget> children = [];
    
    for (var block in blocks) {
      String type = block['type'] ?? 'text';
      String content = block['content'] ?? '';

      if (type == 'text') {
        children.add(MarkdownBody(
          data: _autoFixLatex(content),
          selectable: false, // Changed to false
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.black87),
          ),
          inlineSyntaxes: [LatexSyntax()],
          builders: {
            'latex': LatexElementBuilder(),
          },
        ));
      } else if (type == 'latex_block') {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0), // Add padding for better touch
                child: Math.tex(
                  content,
                  textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), // Larger font
                ),
              ),
            ),
          ),
        ));
      } else if (type == 'svg') {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            padding: const EdgeInsets.all(8.0),
            child: SvgPicture.string(
              content,
              placeholderBuilder: (BuildContext context) => Container(
                padding: const EdgeInsets.all(30.0),
                child: const CircularProgressIndicator(),
              ),
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _autoFixLatex(String text) {
    // 1. LaTeX commands (\frac, \sqrt etc) not wrapped in $
    // Improved regex to handle:
    // - Whitespace: \frac {1} {2}
    // - Nested braces (1 level): \sqrt{1 + \frac{1}{2}}
    text = text.replaceAllMapped(
      RegExp(r'(?<!\$|\\)(\\[a-zA-Z]+(?:\s*\{(?:[^{}]|\{[^{}]*\})*\})*)'), 
      (match) => '\$${match.group(1)}\$',
    );
    
    // 2. Obvious math patterns (x^2, 10^3)
    // Alphabet or number followed by ^ and number
    text = text.replaceAllMapped(
      RegExp(r'(?<!\$)\b([a-zA-Z0-9]+\^[a-zA-Z0-9]+)\b'),
      (match) => '\$${match.group(1)}\$',
    );

    // 3. Simple equations (x = 5, y = ax + b) - conservative approach
    // We avoid aggressive replacement to not break normal text, 
    // but can target specific patterns like "x = ..." if needed.
    // For now, we stick to the user's requested patterns (commands and powers).

    return text;
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            if (_draftImage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                height: 100,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_draftImage!),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _draftImage = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo_library, color: Colors.blue),
                  onPressed: _isTyping ? null : () => _handleImageSelection(ImageSource.gallery),
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.blue),
                  onPressed: _isTyping ? null : () => _handleImageSelection(ImageSource.camera),
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    enabled: !_isTyping,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: _isTyping ? null : (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isTyping ? Icons.stop : Icons.send,
                    color: _isTyping ? Colors.red : Colors.blue,
                  ),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


