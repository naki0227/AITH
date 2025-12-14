import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/latex_syntax.dart';
import '../utils/latex_builder.dart';

class ChallengeDialog extends StatefulWidget {
  final Map<String, dynamic> challenge;
  final String Function(String) autoFixLatex; // Pass the fixer function

  const ChallengeDialog({super.key, required this.challenge, required this.autoFixLatex});

  @override
  State<ChallengeDialog> createState() => _ChallengeDialogState();
}

class _ChallengeDialogState extends State<ChallengeDialog> {
  int? _selectedOption;
  bool _isAnswered = false;

  void _checkAnswer(int index) {
    setState(() {
      _selectedOption = index;
      _isAnswered = true;
    });
  }

  Widget _buildMarkdown(String text) {
    return MarkdownBody(
      data: widget.autoFixLatex(text),
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
    final question = widget.challenge['question'];
    final referenceSvg = widget.challenge['reference_svg'];
    final options = List<String>.from(widget.challenge['options']);
    final answerIndex = widget.challenge['answer_index'];
    final explanation = widget.challenge['explanation'];

    return AlertDialog(
      title: const Text("🔥 類題に挑戦！"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (referenceSvg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  padding: const EdgeInsets.all(8.0),
                  child: SvgPicture.string(referenceSvg),
                ),
              ),
            _buildMarkdown(question),
            const SizedBox(height: 16),
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
                child: ListTile(
                  title: _buildMarkdown(options[index]),
                  leading: _isAnswered
                      ? (index == answerIndex
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (index == _selectedOption
                              ? const Icon(Icons.cancel, color: Colors.red)
                              : null))
                      : null,
                  onTap: _isAnswered ? null : () => _checkAnswer(index),
                ),
              );
            }),
            if (_isAnswered) ...[
              const SizedBox(height: 16),
              Text(
                _selectedOption == answerIndex ? "正解！🎉" : "残念...😢",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _selectedOption == answerIndex ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              _buildMarkdown("解説: $explanation"),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("閉じる"),
        ),
      ],
    );
  }
}
